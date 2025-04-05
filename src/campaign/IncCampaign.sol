// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IIncCampaign} from "./interfaces/IIncCampaign.sol";
import "./interfaces/IIncDoorFactory.sol";

contract IncDoor is IIncCampaign, AccessControl {
    using Math for uint256;
    using SafeERC20 for IERC20;

    bytes32 public constant CAMPAIGN_ADMIN_ROLE = keccak256("CAMPAIGN_ADMIN_ROLE");
    uint256 private constant BPS_DENOMINATOR = 10_000;
    address public constant NATIVE_TOKEN = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    IIncDoorFactory public immutable factory;

    // Campaign Configuration
    uint32 public immutable holdingPeriodInSeconds;
    uint256 public immutable targetAmount;
    address public immutable targetToken;
    address public immutable donationReceiver;
    uint256 public immutable startTimestamp;

    // Fee parameter in basis points (1000 = 10%)
    uint16 public feeBps;
    bool public isCampaignActive;
    // Unique identifier for this campaign
    uint256 public immutable campaignId;

    // Scaling factors for 18 decimal normalization
    uint256 public immutable targetScalingFactor;
    uint256 public immutable rewardScalingFactor;

    // Campaign State
    uint256 public pID;
    uint256 public totalReallocatedAmount;
    uint256 public accumulatedFees;

    // Track whether campaign was manually deactivated
    bool private _manuallyDeactivated;

    // Participations
    mapping(uint256 pID => Participation) public participations;

    /// @notice Creates a new campaign with specified parameters
    /// @param holdingPeriodInSeconds_ Duration users must hold tokens
    /// @param targetToken_ Address of token users need to hold
    /// @param rewardToken_ Address of token used for rewards
    /// @param rewardPPQ_ Amount of reward tokens earned for participating in the campaign, in parts per quadrillion
    /// @param campaignAdmin Address granted CAMPAIGN_ADMIN_ROLE
    /// @param startTimestamp_ When the campaign becomes active (0 for immediate)
    /// @param feeBps_  fee percentage in basis points
    /// @param alternativeWithdrawalAddress_ Optional alternative address for withdrawing unallocated rewards (zero
    /// address to re-use `campaignAdmin`)
    /// @param campaignId_ Unique identifier for this campaign
    constructor(
        uint32 holdingPeriodInSeconds_,
        uint256 fundraisingAmount,
        address targetToken_,
        address campaignAdmin,
        uint256 startTimestamp_,
        uint16 feeBps_,
        address donationReceiver,
        uint256 campaignId_
    ) {
      

        if (startTimestamp_ != 0 && startTimestamp_ <= block.timestamp) {
            revert InvalidCampaignSettings();
        }

        factory = IIncDoorFactory(msg.sender);

        targetToken = targetToken_;
        campaignId = campaignId_;

        // Compute scaling factors based on token decimals
        uint256 targetDecimals = targetToken_ == NATIVE_TOKEN ? 18 : IERC20Metadata(targetToken_).decimals();


        _grantRole(CAMPAIGN_ADMIN_ROLE, campaignAdmin);

        startTimestamp = startTimestamp_ == 0 ? block.timestamp : startTimestamp_;

        // Campaign is active if start time is now or in the past
        isCampaignActive = startTimestamp <= block.timestamp;

        // Initialize as not manually deactivated
        _manuallyDeactivated = false;
        holdingPeriodInSeconds = holdingPeriodInSeconds_;
        targetAmount = fundraisingAmount;
        feeBps = feeBps_;
        donationReceiver = donationReceiver;
    }

    modifier whenNotPaused() {
        if (factory.isCampaignPaused(address(this))) revert CampaignPaused();
        _;
    }

    modifier onlyFactoryOrIncDoorAdmin() {
        if (!factory.hasRole(factory.INCDOOR_ADMIN_ROLE(), msg.sender) && msg.sender != address(factory)) {
            revert Unauthorized();
        }
        _;
    }

    
    modifier onlyIncDoorOperator() {
        if (!factory.hasRole(factory.INCDOOR_OPERATOR_ROLE(), msg.sender)) {
            revert Unauthorized();
        }
        _;
    }

    modifier onlyCampaignAdmin() {
    // Check if msg.sender does not have the campaign admin role and revert if so.
    if (!hasRole(CAMPAIGN_ADMIN_ROLE, msg.sender)) {
        revert("Caller is not a campaign admin");
    }
    _;
}

   

    /// @notice Handles token reallocation for campaign participation
    /// @param campaignId_ ID of the campaign
    /// @param userAddress Address of the participating user
    /// @param toToken Address of the token being acquired
    function participate(
        uint256 campaignId_,
        address userAddress,
        address toToken
    ) external payable whenNotPaused {
        // Check if campaign is active or can be activated
        _validateAndActivateCampaignIfReady();

        if (toToken != targetToken) {
            revert InvalidToTokenReceived(toToken);
        }

        if (campaignId_ != campaignId) {
            revert InvalidCampaignId();
        }
        uint256 balanceBefore = getBalanceOfSelf(targetToken);
        if(balanceBefore > targetAmount) revert CampaignRaisedFundGoal();
        uint256 amountReceived;
        if (targetToken == NATIVE_TOKEN) {
            amountReceived = msg.value;
        } else {
            if (msg.value > 0) {
                revert InvalidToTokenReceived(NATIVE_TOKEN);
            }
            IERC20 tokenReceived = IERC20(targetToken);
            uint256 balanceOfSender = tokenReceived.balanceOf(msg.sender);
            uint256 balanceBefore = getBalanceOfSelf(targetToken);

            SafeERC20.safeTransferFrom(tokenReceived, msg.sender, address(this), balanceOfSender);

            amountReceived = getBalanceOfSelf(toToken) - balanceBefore;
        }
       
       accumulatedFees += (amountReceived * feeBps) / BPS_DENOMINATOR;

        totalReallocatedAmount += amountReceived;

        pID++;
        participations[pID] = Participation({
            status: ParticipationStatus.PARTICIPATING,
            userAddress: userAddress,
            toAmount: amountReceived,
            startTimestamp: block.timestamp,
            startBlockNumber: block.number
        });

        emit NewParticipation(campaignId_, userAddress, pID, amountReceived, userRewards, fees, data);
    }

    function enoughFundsRaised() internal view returns (bool) {
        uint256 balance = getBalanceOfSelf(targetToken);
    return balance >= targetAmount;
}

    /// @notice Callable by everyone, only when holdingPeriodInSeconds is reached and campaign is not more active.
    /// @notice Sends the donation amount to donationReceiver.
    function reallocateTokens() public {
        if (block.timestamp < startTimestamp_ + holdingPeriodInSeconds_) revert CampaignIsStillActive();

        
         if (targetToken == NATIVE_TOKEN) {
            (bool success, ) = donationReceiver.call{value: totalReallocatedAmount}("");
            require(success, "Native token transfer failed");
        } else {
             IERC20 token = IERC20(targetToken);
            SafeERC20.safeTransfer(token, donationReceiver, totalReallocatedAmount);
        }

        isCampaignActive = false;
    }

    /// @notice Checks if campaign is active or can be activated based on current timestamp
    function _validateAndActivateCampaignIfReady() internal {
        if (!isCampaignActive) {
            // Only auto-activate if campaign has not been manually deactivated
            // and if the start time has been reached
            if (!_manuallyDeactivated && block.timestamp >= startTimestamp) {
                // Automatically activate the campaign if start time reached
                isCampaignActive = true;
            } else if (block.timestamp < startTimestamp) {
                // If start time not reached, explicitly revert
                revert StartDateNotReached();
            } else {
                // If campaign was manually deactivated, revert with InactiveCampaign
                revert InactiveCampaign();
            }
        }
    }

   

    /*//////////////////////////////////////////////////////////////////////////
                              ADMIN FUNCTIONS                             
  //////////////////////////////////////////////////////////////////////////*/

    /// @notice Collects accumulated fees
    /// @return feesToCollect Amount of fees collected
    function collectFees() external onlyFactoryOrIncDoorAdmin returns (uint256 feesToCollect) {
        feesToCollect = accumulatedFees;
        accumulatedFees = 0;

        _transfer(rewardToken, factory, feesToCollect);

        emit FeesCollected(feesToCollect);
    }

    /// @notice Marks a campaign as active, i.e accepting new participations
    /// @param isActive New active status
    function setIsCampaignActive(bool isActive) external onlyCampaignAdmin{
        if (isActive && block.timestamp < startTimestamp) {
            revert StartDateNotReached();
        }

        isCampaignActive = isActive;
        // If deactivating, mark as manually deactivated
        if (!isActive) {
            _manuallyDeactivated = true;
        } else {
            // If activating, clear the manual deactivation flag
            _manuallyDeactivated = false;
        }

        emit CampaignStatusChanged(isActive);
    }

    /// @notice Rescues tokens that were mistakenly sent to the contract
    /// @return amount Amount of tokens rescued
    function rescueTokens(address token) external returns (uint256 amount) {
        if (!factory.hasRole(factory.INCDOOR_ADMIN_ROLE(), msg.sender)) {
            revert Unauthorized();
        }

        if (token == rewardToken) {
            revert CannotRescueRewardToken();
        }

        amount = getBalanceOfSelf(token);
        if (amount > 0) {
            _transfer(token, msg.sender, amount);
            emit TokensRescued(token, amount);
        }

        return amount;
    }

    /*//////////////////////////////////////////////////////////////////////////
                              VIEW FUNCTIONS                              
  //////////////////////////////////////////////////////////////////////////*/

    /// @notice Gets the balance of the specified token for this contract
    /// @param token Address of token to check
    /// @return Balance of the token
    function getBalanceOfSelf(address token) public view returns (uint256) {
        if (token == NATIVE_TOKEN) {
            return address(this).balance;
        } else {
            return IERC20(token).balanceOf(address(this));
        }
    }


    /*//////////////////////////////////////////////////////////////////////////
                            INTERNAL FUNCTIONS
  //////////////////////////////////////////////////////////////////////////*/
    /// @notice Internal function to transfer tokens
    /// @dev Handles both ERC20 and native token transfers
    function _transfer(address token, address to, uint256 amount) internal {
        if (token == NATIVE_TOKEN) {
            (bool sent, ) = to.call{value: amount}("");
            if (!sent) revert NativeTokenTransferFailed();
        } else {
            SafeERC20.safeTransfer(IERC20(token), to, amount);
        }
    }

    /// @notice Allows contract to receive native token transfers
    receive() external payable {}

    /// @notice Fallback function to receive native token transfers
    fallback() external payable {}
}
