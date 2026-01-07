import hardhatToolboxMochaEthersPlugin from "@nomicfoundation/hardhat-toolbox-mocha-ethers"
import hardhatVerify from "@nomicfoundation/hardhat-verify"
import 'dotenv/config'
import { defineConfig } from "hardhat/config"

const INFURA_KEY = process.env.INFURA_API_KEY
const DEPLOYER = process.env.SEPOLIA_PRIVATE_KEY

export default defineConfig({
  plugins: [hardhatToolboxMochaEthersPlugin, hardhatVerify],
  solidity: { version: "0.8.28" },
  networks: {
    sepolia: {
      type: "http",
      chainType: "l1",
      url: `https://sepolia.infura.io/v3/${INFURA_KEY}`,
      accounts: DEPLOYER ? [DEPLOYER] : [],
    },
  },
  verify: { etherscan: { apiKey: process.env.ETHERSCAN_API_KEY ?? "" } },
})
