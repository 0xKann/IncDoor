// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./IBaseIncDoor.sol";

interface IIncCampaign is IBaseIncDoor {
    // Errors
    error NotEnoughRewardsAvailable();
    error InactiveCampaign();
    error StartDateNotReached();
    error InvalidCampaignSettings();
    error EmptyClaimArray();
    error HoldingPeriodNotElapsed(uint256 pID);
    error UnauthorizedCaller(uint256 pID);
    error InvalidParticipationStatus(uint256 pID);
    error NativeTokenTransferFailed();
    error EmptyParticipationsArray();
    error InvalidCampaignId();
    error CannotRescueRewardToken();
    error CampaignIsStillActive();

    // Events
    event FeesCollected(uint256 amount);
    event CampaignStatusChanged(bool isActive);
    event TokensRescued(address token, uint256 amount);

    function collectFees() external returns (uint256);
    function setIsCampaignActive(bool isActive) external;
    function rescueTokens(address token) external returns (uint256);

    // View functions
    function getBalanceOfSelf(address token) external view returns (uint256);
   
}
