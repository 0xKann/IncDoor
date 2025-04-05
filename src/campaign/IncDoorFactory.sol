// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Create2.sol";
import "./IncCampaign.sol";
import "./interfaces/IIncDoorFactory.sol";


contract IncDoorFactory is IIncDoorFactory, AccessControl {
    using SafeERC20 for IERC20;

    bytes32 public constant INCDOOR_ADMIN_ROLE = keccak256("INCDOOR_ADMIN_ROLE");
    bytes32 public constant INCDOOR_OPERATOR_ROLE = keccak256("INCDOOR_OPERATOR_ROLE");


    uint16 public FEE_BPS = 100; // 1% by default

    // Campaign tracking
    mapping(address => bool) public isCampaign;
    address[] public campaignAddresses;
    mapping(address => bool) public isCampaignPaused;

   
    constructor(address admin_, address operator_) {
        if (treasury_ == address(0)) revert InvalidTreasuryAddress();
        if (admin_ == address(0)) revert ZeroAddress();
        if (operator_ == address(0)) revert ZeroAddress();
        if (swapCaller_ == address(0)) revert ZeroAddress();


        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(INCDOOR_ADMIN_ROLE, admin_);
        _grantRole(INCDOOR_OPERATOR_ROLE, operator_);
    }

    function isCampaignDeployed() public view returns(bool){

    }

    /// @notice Deploys a new donation goal campaign contract
    /// @dev Uses Create2 for unique address generation
    function deployCampaign(
        uint32 holdingPeriodInSeconds,
        address targetToken,
        address campaignAdmin,
        address donationReceiver,
        uint256 startTimestamp,
        uint256 uuid
    ) public returns (address campaign) {
        if (campaignAdmin == address(0)) revert ZeroAddress();
        if (targetToken == address(0)) revert ZeroAddress();
        if (holdingPeriodInSeconds == 0) revert InvalidParameter();

        // Generate deterministic salt using all parameters
        bytes32 salt = keccak256(
            abi.encode(
                holdingPeriodInSeconds,
                targetToken,
                campaignAdmin,
                donationReceiver,
                startTimestamp,
                FEE_BPS,
                uuid
            )
        );

        // Create constructor arguments
        bytes memory constructorArgs = abi.encode(
            holdingPeriodInSeconds,
            targetToken,
            campaignAdmin,
            startTimestamp,
            FEE_BPS,
            donationReceiver,
            uuid
        );

        // Deploy Create2
        bytes memory bytecode = abi.encodePacked(type(IncDoorCampaign).creationCode, constructorArgs);
        campaign = Create2.deploy(0, salt, bytecode);

        // save campaing address to mapping
        isCampaign[campaign] = true;
        campaignAddresses.push(campaign);

        emit CampaignDeployed(campaign, campaignAdmin, targetToken, startTimestamp, uuid);
    }

    /// @notice Deploys a new donation campaign and funds it
    function deployAndFundCampaign(
        uint32 holdingPeriodInSeconds,
        address targetToken,
        address campaignAdmin,
        uint256 startTimestamp,
        address donationReceiver,
        uint256 initialDonationAmount,
        uint256 uuid
        //add goal
    ) external payable returns (address campaign) {
        if (campaignAdmin == address(0)) revert ZeroAddress();
        if (targetToken == address(0)) revert ZeroAddress();
        if (donationReceiver == address(0)) revert ZeroAddress();
        if (holdingPeriodInSeconds == 0) revert InvalidParameter();

        if (rewardToken == NATIVE_TOKEN) {
            if (msg.value != initialRewardAmount) revert IncorrectEtherAmount();
            // Deploy contract first
            campaign = deployCampaign(
                holdingPeriodInSeconds,
                targetToken,
                campaignAdmin,
                startTimestamp,
                donationReceiver,
                uuid
            );
            // Then send ETH
            (bool sent, ) = campaign.call{value: initialRewardAmount}("");
            if (!sent) revert NativeTokenTransferFailed();
        } else {
            if (msg.value > 0) revert IncorrectEtherAmount();

            campaign = deployCampaign(
               holdingPeriodInSeconds,
                targetToken,
                campaignAdmin,
                startTimestamp,
                donationReceiver,
                uuid
            );
            IERC20(rewardToken).safeTransferFrom(msg.sender, campaign, initialRewardAmount);
        }
    }

   
    function getCampaignAddress(
        uint32 holdingPeriodInSeconds,
        address targetToken,
        address campaignAdmin,
        address donationReceiver,
        uint256 startTimestamp,
        uint256 uuid
    ) external view returns (address computedAddress) {
        bytes32 salt = keccak256(
            abi.encode(
                holdingPeriodInSeconds,
                targetToken,
                campaignAdmin,
                donationReceiver,
                startTimestamp,
                FEE_BPS,
                uuid
            )
        );

        bytes memory constructorArgs = abi.encode(
           holdingPeriodInSeconds,
                targetToken,
                campaignAdmin,
                donationReceiver,
                startTimestamp,
                uuid
        );

        bytes memory bytecode = abi.encodePacked(type(IncDoorCampaign).creationCode, constructorArgs);

        computedAddress = Create2.computeAddress(salt, keccak256(bytecode), address(this));
    }

    

    /// @notice Update  fee in basis points for future campaigns created by this factory
    /// @param newFeeBps New fee in basis points
    /// @dev Only callable by INCDOOR_ADMIN_ROLE
    function updateFeeSetting(uint16 newFeeBps) external onlyRole(INCDOOR_ADMIN_ROLE) {
        if (newFeeBps > 10_000) revert InvalidFeeSetting();

        uint16 oldFeeBps = FEE_BPS;
        FEE_BPS = newFeeBps;
        emit FeeUpdated(oldFeeBps, newFeeBps);
    }

    /// @notice Collects accumulated fees from multiple campaigns
    /// @param campaigns Array of campaign addresses to collect fees from
    /// @dev Only callable by INCDOOR_OPERATOR_ROLE
    function collectFeesFromCampaigns(address[] calldata campaigns) external onlyRole(INCDOOR_OPERATOR_ROLE) {
        uint256 totalAmount;

        for (uint256 i = 0; i < campaigns.length; i++) {
            if (!isCampaign[campaigns[i]]) revert InvalidCampaign();
            totalAmount += IncDoor(payable(campaigns[i])).collectFees();
        }

        emit FeesCollected(campaigns, totalAmount);
    }

    /// @notice Pauses multiple campaigns
    /// @param campaigns Array of campaign addresses to pause
    /// @dev Only callable by INCDOOR_ADMIN_ROLE
    function pauseCampaigns(address[] calldata campaigns) external onlyRole(INCDOOR_ADMIN_ROLE) {
        for (uint256 i = 0; i < campaigns.length; i++) {
            if (!isCampaign[campaigns[i]]) revert InvalidCampaign();
            if (isCampaignPaused[campaigns[i]]) revert CampaignAlreadyPaused();

            isCampaignPaused[campaigns[i]] = true;
        }

        emit CampaignsPaused(campaigns);
    }

    /// @notice Unpauses multiple campaigns
    /// @param campaigns Array of campaign addresses to unpause
    /// @dev Only callable by INCDOOR_ADMIN_ROLE
    function unpauseCampaigns(address[] calldata campaigns) external onlyRole(INCDOOR_ADMIN_ROLE) {
        for (uint256 i = 0; i < campaigns.length; i++) {
            if (!isCampaign[campaigns[i]]) revert InvalidCampaign();
            if (!isCampaignPaused[campaigns[i]]) revert CampaignNotPaused();

            isCampaignPaused[campaigns[i]] = false;
        }

        emit CampaignsUnpaused(campaigns);
    }

    receive() external payable {}

    fallback() external payable {}


}
