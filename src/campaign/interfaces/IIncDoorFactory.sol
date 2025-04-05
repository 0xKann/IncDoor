// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/IAccessControl.sol";

interface IIncDoorFactory is IAccessControl {
    function INCDOOR_ADMIN_ROLE() external view returns (bytes32);
    function INCDOOR_OPERATOR_ROLE() external view returns (bytes32);
    function NATIVE_TOKEN() external view returns (address);

    error ZeroAddress();
    error InvalidParameter();
    error InvalidCampaign();
    error CampaignAlreadyPaused();
    error CampaignNotPaused();
    error NativeTokenTransferFailed();
    error IncorrectEtherAmount();
    error InvalidFeeSetting();

    event CampaignDeployed(
        address indexed campaign,
        address indexed admin,
        address targetToken,
        uint256 startTimestamp,
        uint256 uuid
    );
    event CampaignsPaused(address[] campaigns);
    event CampaignsUnpaused(address[] campaigns);
    event FeesCollected(address[] campaigns, uint256 totalAmount);
    event FeeUpdated(uint16 oldFeeBps, uint16 newFeeBps);

    function isCampaign(address) external view returns (bool);
    function campaignAddresses(uint256) external view returns (address);
    function isCampaignPaused(address) external view returns (bool);

    function deployCampaign(
       uint32 holdingPeriodInSeconds,
        address targetToken,
        address campaignAdmin,
        address donationReceiver,
        uint256 startTimestamp,
        uint256 uuid
    ) external returns (address);

    function deployAndFundCampaign(
        uint32 holdingPeriodInSeconds,
        address targetToken,
        address campaignAdmin,
        uint256 startTimestamp,
        address donationReceiver,
        uint256 initialDonationAmount,
        uint256 uuid
    ) external payable returns (address);

    function getCampaignAddress(
        uint32 holdingPeriodInSeconds,
        address targetToken,
        address campaignAdmin,
        address donationReceiver,
        uint256 startTimestamp,
        uint256 uuid
    ) external view returns (address);

    function updateFeeSetting(uint16 newFeeBps) external;
    function collectFeesFromCampaigns(address[] calldata campaigns) external;
    function pauseCampaigns(address[] calldata campaigns) external;
    function unpauseCampaigns(address[] calldata campaigns) external;
}
