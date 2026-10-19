const hre = require("hardhat");
async function main() {
  const Hub = await hre.ethers.getContractFactory("NexusPropertyFractionalizer");
  const hub = await Hub.deploy();
  await hub.deployed();
  console.log("Property Fractionalizer deployed to:", hub.address);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
