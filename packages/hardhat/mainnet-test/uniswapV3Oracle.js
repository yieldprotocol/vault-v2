const { expect } = require("chai");
const { ethers, waffle } = require("hardhat");

const { UniswapV3OracleArtifact } = require("./uniswapabi");
const { deployContract } = waffle;
function bytes6ToBytes32(x) {
	return x + "00".repeat(26);
}

describe("Oracle", function () {
	var oracle;
	const fraxId = ethers.utils.hexlify("0x853d955acef8"); //FRAX
	const usdcId = ethers.utils.hexlify("0xa0b86991c621"); //USDC
	const wethId = ethers.utils.hexlify("0xC02aaA39b223");
	const uniId = ethers.utils.hexlify("0x1f9840a85d5a");
	const wbtcId = ethers.utils.hexlify("0x2260FAC5E554");
	const fraxusdcPoolAddress = "0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52";
	const usdcEthPoolAddress = "0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8";
	const uniEthPoolAddress = "0x1d42064Fc4Beb5F8aAF85F4617AE8b3b5B8Bd801";
	const wbtcUsdcPoolAddress = "0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35";
	before(async () => {
		const signers = await ethers.getSigners();
		ownerAcc = signers[0];
		owner = await ownerAcc.getAddress();
		oracle = await deployContract(ownerAcc, UniswapV3OracleArtifact, []); // Oracle.deploy();
		// await oracle.deployed();

		await oracle.setSource(fraxId, usdcId, fraxusdcPoolAddress, 100)
		await oracle.setSource(usdcId, wethId, usdcEthPoolAddress, 100)
		await oracle.setSource(uniId, wethId, uniEthPoolAddress, 100)
		await oracle.setSource(wbtcId, usdcId, wbtcUsdcPoolAddress, 100)
	});

	it("FRAX/USDC", async function () {
		var temp = await oracle.callStatic.get(
			bytes6ToBytes32(usdcId),
			bytes6ToBytes32(fraxId),
			ethers.BigNumber.from("1000000")
		);

		console.log("1 USDC equals " + (temp[0] / 1e18).toString() + " FRAX");

		temp = await oracle.callStatic.get(
			bytes6ToBytes32(fraxId),
			bytes6ToBytes32(usdcId),
			ethers.BigNumber.from("1000000000000000000")
		);

		console.log("1 FRAX equals " + (temp[0] / 1e6).toString() + " USDC");
	});

	it("USDC/ETH", async function () {
		var temp = await oracle.callStatic.get(
			bytes6ToBytes32(usdcId),
			bytes6ToBytes32(wethId),
			ethers.BigNumber.from("1000000")
		);

		console.log("1 USDC equals " + (temp[0] / 1e18).toString() + " WETH");

		temp = await oracle.callStatic.get(
			bytes6ToBytes32(wethId),
			bytes6ToBytes32(usdcId),
			ethers.BigNumber.from("1000000000000000000")
		);

		console.log("1 WETH equals " + (temp[0] / 1e6).toString() + " USDC");
	});

	it("UNI/ETH", async function () {
		var temp = await oracle.callStatic.get(
			bytes6ToBytes32(uniId),
			bytes6ToBytes32(wethId),
			ethers.BigNumber.from("1000000000000000000")
		);

		console.log("1 UNI equals " + (temp[0] / 1e18).toString() + " WETH");

		temp = await oracle.callStatic.get(
			bytes6ToBytes32(wethId),
			bytes6ToBytes32(uniId),
			ethers.BigNumber.from("1000000000000000000")
		);

		console.log("1 WETH equals " + (temp[0] / 1e18).toString() + " UNI");
	});

	it("WBTC/USDC", async function () {
		var temp = await oracle.callStatic.get(
			bytes6ToBytes32(wbtcId),
			bytes6ToBytes32(usdcId),
			ethers.BigNumber.from("100000000")
		);

		console.log("1 WBTC equals " + (temp[0] / 1e6).toString() + " USDC");

		temp = await oracle.callStatic.get(
			bytes6ToBytes32(usdcId),
			bytes6ToBytes32(wbtcId),
			ethers.BigNumber.from("1000000")
		);

		console.log("1 USDC equals " + (temp[0] / 1e8).toString() + " WBTC");
	});
});