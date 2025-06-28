require("@nomicfoundation/hardhat-toolbox");

module.exports = {
    solidity: {
        compilers: [
            {
                version: "0.8.28",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 200
                    }
                }
            },
            {
                version: "0.8.9",
                settings: {
                    viaIR: true,
                    optimizer: {
                        enabled: true,
                        runs: 200
                    }
                }
            }
        ]
    }
};
