// ignition/modules/deploy-main.js
const { buildModule } = require("@nomicfoundation/hardhat-ignition/modules");

module.exports = buildModule("MainModule", (m) => {
    const main = m.contract("Main");
    return { main };
});
