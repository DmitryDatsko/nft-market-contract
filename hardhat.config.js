require("dotenv").config();
require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-ignition-ethers");

const { PRIVATE_KEY = "" } = process.env;

module.exports = {
    solidity: {
        version: "0.8.28",
        settings: {
            metadata: {
                bytecodeHash: "none", // disable ipfs
                useLiteralContent: true, // use source code
            },
        },
    },
    networks: {
        monadTestnet: {
            url: "https://testnet-rpc.monad.xyz",
            accounts: [PRIVATE_KEY],
            chainId: 10143,
        },
    },
    sourcify: {
        enabled: true,
        apiUrl: "https://sourcify-api-monad.blockvision.org",
        browserUrl: "https://testnet.monadexplorer.com",
    },
    // To avoid errors from Etherscan
    etherscan: {
        enabled: false,
    },
};
