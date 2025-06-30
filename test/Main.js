const { expect } = require("chai");
const { ethers } = require("hardhat");

const {
    loadFixture,
} = require("@nomicfoundation/hardhat-toolbox/network-helpers");

describe("Main contrac", function () {
    let hardhatToken, owner, user1, user2, user3;

    beforeEach(async function () {
        ({ hardhatToken, owner, user1, user2, user3 } = await loadFixture(deployMainFixture));
    })

    async function deployMainFixture() {
        const [owner, user1, user2, user3] = await ethers.getSigners();

        const hardhatToken = await ethers.deployContract("Main");

        await hardhatToken.waitForDeployment();

        return { hardhatToken, owner, user1, user2, user3 };
    }

    describe("Contract constructor", function () {
        it("Should set up owner", async function () {
            expect(await hardhatToken.owner()).to.equal(owner.address);
        });
    });

    describe("TransferOwnership function", function () {
        it("Should revert when not owner call function", async function () {
            await expect(hardhatToken.connect(user1).transferOwnership(user1.address))
                .to.be.revertedWithCustomError(hardhatToken, "OwnableUnauthorizedAccount")
                .withArgs(user1.address);
        });

        it("Should set the new owner", async function () {
            expect(await hardhatToken.connect(owner).transferOwnership(user1.address))
                .to.emit(hardhatToken, "OwnershipTransferred")
                .withArgs(owner.address, user1.address);
        });

        it("Should revert for address(0)", async function () {
            await expect(hardhatToken.connect(owner).transferOwnership(ethers.ZeroAddress))
                .to.be.revertedWithCustomError(hardhatToken, "OwnableInvalidOwner")
                .withArgs(ethers.ZeroAddress);
        });

        it("Should revert if old owner equal new owner", async function () {
            await expect(hardhatToken.connect(owner).transferOwnership(owner.address))
                .to.be.revertedWithCustomError(hardhatToken, "OwnableInvalidOwner")
                .withArgs(owner.address);
        });
    });

    describe("Pause function", function () {
        it("Should revert when called by non-owner", async function () {
            await expect(hardhatToken.connect(user1).pause())
                .to.be.revertedWithCustomError(hardhatToken, "OwnableUnauthorizedAccount")
                .withArgs(user1.address);
        });

        it("Should emit when called by owner", async function () {
            await expect(hardhatToken.connect(owner).pause())
                .to.emit(hardhatToken, "Paused")
                .withArgs(owner.address);
        });

        it("Should revert when conract already on pause", async function () {
            await hardhatToken.connect(owner).pause();

            await expect(hardhatToken.connect(owner).pause())
                .to.be.revertedWithCustomError(hardhatToken, "EnforcedPause")
                .withArgs("Contract on pause");
        });
    });

    describe("Unpause function", function () {
        it("Should revert when called by non-owner", async function () {
            await hardhatToken.connect(owner).pause();

            await expect(hardhatToken.connect(user1).unpause())
                .to.be.revertedWithCustomError(hardhatToken, "OwnableUnauthorizedAccount")
                .withArgs(user1.address);
        });

        it("Should emit when called by owner", async function () {
            await hardhatToken.connect(owner).pause();

            await expect(hardhatToken.connect(owner).unpause())
                .to.emit(hardhatToken, "Unpaused")
                .withArgs(owner.address);
        });

        it("Should revert when conract already unpaused", async function () {
            await expect(hardhatToken.connect(owner).unpause())
                .to.be.revertedWithCustomError(hardhatToken, "EnforcedPause")
                .withArgs("Contract not on pause");
        });
    });

    describe("balanceOf function", function () {
        it("Should return user balance", async function () {
            expect(await hardhatToken.connect(user1).balanceOf(user1.address))
                .to.be.equal(0);
        });
    });

    describe("deposit function", function () {
        it("Should emit deposited", async function () {
            const depositAmount = ethers.parseEther("1.0");
            await expect(hardhatToken.connect(user1).deposit({ value: depositAmount }))
                .to.emit(hardhatToken, "Deposited")
                .withArgs(user1.address, depositAmount);
        });

        it("Should revert when deposit amount is zero", async function () {
            await expect(hardhatToken.connect(user1).deposit({ value: 0 }))
                .to.be.revertedWithCustomError(hardhatToken, "DepositInsufficientValue")
                .withArgs("Less than accepted");
        });

        it("Should revert when contract is paused", async function () {
            await hardhatToken.connect(owner).pause();

            await expect(hardhatToken.connect(user1).deposit({ value: ethers.parseEther("1.0") }))
                .to.be.revertedWithCustomError(hardhatToken, "EnforcedPause")
                .withArgs("Contract on pause");
        });
    });
});
