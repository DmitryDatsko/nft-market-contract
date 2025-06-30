const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Main Marketplace batch operations", function () {
    let Main, MockERC721, mockERC721, marketplace;
    let owner, user1, user2;

    beforeEach(async () => {
        [owner, user1, user2] = await ethers.getSigners();

        MockERC721 = await ethers.getContractFactory("MockERC721");
        mockERC721 = await MockERC721.deploy();

        await mockERC721.mint(user1.address, 1);
        await mockERC721.mint(user1.address, 2);
        await mockERC721.mint(user2.address, 3);

        Main = await ethers.getContractFactory("Main");
        marketplace = await Main.deploy();

        const marketplaceAddr = await marketplace.getAddress();
        await mockERC721.connect(user1).setApprovalForAll(marketplaceAddr, true);
        await mockERC721.connect(user2).setApprovalForAll(marketplaceAddr, true);
    });

    describe("listNFTs / cancelListings", () => {
        it("lists multiple NFTs and then cancels some of them", async () => {
            const mkAddr = await mockERC721.getAddress();
            await expect(
                marketplace.connect(user1).listNFTs(
                    [mkAddr, mkAddr],
                    [1, 2],
                    [ethers.parseEther("1"), ethers.parseEther("2")]
                )
            )
                .to.emit(marketplace, "NFTListed")
                .withArgs(user1.address, mkAddr, 1, ethers.parseEther("1"))
                .and.to.emit(marketplace, "NFTListed")
                .withArgs(user1.address, mkAddr, 2, ethers.parseEther("2"));

            await expect(
                marketplace.connect(user2).cancelListings(
                    [mkAddr],
                    [1]
                )
            ).to.be.revertedWithCustomError(marketplace, "NFTsNotListed");

            await expect(
                marketplace.connect(user1).cancelListings(
                    [mkAddr],
                    [2]
                )
            )
                .to.emit(marketplace, "NFTDelisted")
                .withArgs(user1.address, mkAddr, 2);

            const encodeKey = (contract, id) =>
                ethers.keccak256(
                    ethers.AbiCoder.defaultAbiCoder().encode(
                        ["address", "uint256"],
                        [contract, id]
                    )
                );

            const key1 = ethers.keccak256(
                ethers.solidityPacked(
                    ["address", "uint256"],
                    [mkAddr, 1]
                )
            );
            const key2 = ethers.keccak256(
                ethers.solidityPacked(
                    ["address", "uint256"],
                    [mkAddr, 2]
                )
            );

            const listing1 = await marketplace.listings(key1);
            const listing2 = await marketplace.listings(key2);

            expect(listing1.active).to.be.true;
            expect(listing2.active).to.be.false;
        });
    });

    describe("buyNFTs", () => {
        beforeEach(async () => {
            const mkAddr = await mockERC721.getAddress();
            await marketplace.connect(user2).listNFTs(
                [mkAddr],
                [3],
                [ethers.parseEther("3")]
            );
        });

        it("buys multiple NFTs in one transaction", async () => {
            const mkAddr = await mockERC721.getAddress();
            await mockERC721.mint(user2.address, 4);
            await marketplace.connect(user2).listNFTs(
                [mkAddr],
                [4],
                [ethers.parseEther("1")]
            );

            const total = ethers.parseEther("4");
            await expect(
                marketplace.connect(user1).buyNFTs(
                    [mkAddr, mkAddr],
                    [3, 4],
                    { value: total }
                )
            )
                .to.emit(marketplace, "NFTPurchased")
                .withArgs(user1.address, mkAddr, 3, ethers.parseEther("3"))
                .and.to.emit(marketplace, "NFTPurchased")
                .withArgs(user1.address, mkAddr, 4, ethers.parseEther("1"));

            expect(await mockERC721.ownerOf(3)).to.equal(user1.address);
            expect(await mockERC721.ownerOf(4)).to.equal(user1.address);
        });

        it("reverts if paid wrong total", async () => {
            const mkAddr = await mockERC721.getAddress();
            await expect(
                marketplace.connect(user1).buyNFTs(
                    [mkAddr],
                    [3],
                    { value: ethers.parseEther("1") }
                )
            ).to.be.revertedWith("Wrong ETH amount");
        });
    });
});
