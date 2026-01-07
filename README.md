# Nft Marketplace contract

The contract provides the following capabilities:
- Create listings (transfer NFTs to the contract and set prices).
- Purchase one or more listings in a single transaction with funds distributed to specific sellers.
- Create bilateral NFT trades between users (exchange NFT for NFT, using listings as the receiving party).
- The contract owner can pause/unpause.
- ReentrancyGuard protection and NFT storage (ERC721Holder).
- Limit on the number of NFTs processed per call — maxNftAmount = 10.
- The contract uses the IERC721 (OpenZeppelin) interface and several proprietary auxiliary abstractions: Context, Ownable, Pausable. The code is designed to work with ERC-721 tokens.

# Deployed
Currently only on Sepolia network:
- https://sepolia.etherscan.io/address/0xE50cded46c884A1155AaB946f139ba009Dae983d
