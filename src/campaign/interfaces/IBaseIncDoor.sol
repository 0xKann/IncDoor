// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface IBaseIncDoor {
    // Errors
    error CampaignPaused();
    error Unauthorized();

    // Enums
    enum ParticipationStatus {
        PARTICIPATING,
        INVALIDATED,
        CLAIMED,
        HANDLED_OFFCHAIN
    }

    // Structs
    struct Participation {
        ParticipationStatus status;
        address userAddress;
        uint256 toAmount;
        uint256 startTimestamp;
        uint256 startBlockNumber;
    }

    // Events
    event NewParticipation(
        uint256 indexed campaignId,
        address indexed userAddress,
        uint256 pID,
        uint256 toAmount,
        uint256 fees
    );

    // External functions
    function participate(
        uint256 campaignId,
        address userAddress,
        address toToken,
        uint256 toAmount
    ) external payable;

    // View functions
    function getBalanceOfSelf(address token) external view returns (uint256);
}
