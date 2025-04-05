# IncDoor

IncDoor is a Web3-native donation protocol that brings transparency and accountability to real-world fundraising. With IncDoor, anyone can deploy an onchain donation campaign using a smart contract factory. Each campaign specifies a recipient address and a donation period. Funds collected are automatically transferred to the recipient when the campaign ends — no middlemen, no misuse.

This solves a common problem in real life: when people donate to a campaign (e.g., someone fundraising for medical help), there’s no guarantee the funds reach the intended recipient. IncDoor enforces this trust through smart contracts — donors can verify exactly how much was raised and where the money went, all onchain.

🧩 Project Logic Overview


🏗️ Factory Deployment:

Our platform has a Factory Contract that allows any user to deploy their own campaign contract using CREATE2 and a unique salt.
Campaign creators can:
Choose their own ERC20 token (e.g. USDC, DAI, etc.) for donations or any native token.
Define campaign parameters like fundingGoal, holdingPeriodInSeconds, and recipient.

🎯 Campaign Contract Behavior:
Once deployed:
Anyone can deposit (donate) tokens to participate.
Deposits are tracked, contributing toward a fundingGoal.

🔐 Withdrawal Logic:
A special withdrawal function is exposed to anyone, allowing the transfer of all funds to the donation recipient once the campaign is over.
The campaign is considered "over" in two cases:
Time-based: The holding period has passed (block.timestamp >= startTimestamp + holdingPeriod).
Goal-based: The fundingGoal has already been met.
