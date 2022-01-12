import { ethers } from "hardhat";

async function main() {
  const factory = await ethers.getContractFactory("dGoldToken");
  const dGoldToken = await factory.deploy();

  await dGoldToken.deployed();

  console.log("DGoldToken deployed to:", dGoldToken.address);
}
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
