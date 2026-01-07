import { buildModule } from "@nomicfoundation/hardhat-ignition/modules"

export default buildModule("MainModule", (m) => {
	const main = m.contract("Main")
	return { main }
})