const Vat = artifacts.require('Vat');
const Jug = artifacts.require('Jug');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('Chai');
const Treasury = artifacts.require('Treasury');
const YDai = artifacts.require('YDai');
const Controller = artifacts.require('Controller');

const { WETH, Line, spotName, linel, limits, spot, rate, chi, toRay, subBN } = require("./utils");

const setupYield = async(owner, user) => {
    // Set up vat, join and weth
    vat = await Vat.new();
    await vat.init(WETH, { from: owner }); // Set WETH rate to 1.0

    weth = await Weth.new({ from: owner });
    wethJoin = await GemJoin.new(vat.address, WETH, weth.address, { from: owner });

    dai = await ERC20.new(0, { from: owner });
    daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

    // Setup vat
    await vat.file(WETH, spotName, spot, { from: owner });
    await vat.file(WETH, linel, limits, { from: owner });
    await vat.file(Line, limits); 
    await vat.fold(WETH, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

    // Setup pot
    pot = await Pot.new(vat.address);

    // Setup chai
    chai = await Chai.new(
        vat.address,
        pot.address,
        daiJoin.address,
        dai.address,
    );

    await pot.setChi(chi, { from: owner });

    // Setup jug
    jug = await Jug.new(vat.address);
    await jug.init(WETH, { from: owner }); // Set WETH duty (stability fee) to 1.0

    // Permissions
    await vat.rely(vat.address, { from: owner });
    await vat.rely(wethJoin.address, { from: owner });
    await vat.rely(daiJoin.address, { from: owner });
    await vat.rely(pot.address, { from: owner });
    await vat.rely(jug.address, { from: owner });
    await vat.hope(daiJoin.address, { from: user });

    treasury = await Treasury.new(
        vat.address,
        weth.address,
        dai.address,
        wethJoin.address,
        daiJoin.address,
        pot.address,
        chai.address,
    );
    await treasury.orchestrate(owner);

    return {
        vat,
        weth,
        wethJoin,
        dai,
        daiJoin,
        pot,
        jug,
        chai,
        treasury
    }
}

// Helper for deploying YDai
async function newYdai(maturity, name, symbol) {
    return YDai.new(
        vat.address,
        jug.address,
        pot.address,
        treasury.address,
        maturity,
        name,
        symbol,
    );
}

// Deploys the controller with 2 Ydai contracts with maturities at 1000 and 
// 2000 blocks from now
async function setupYdaiController(owner) {
    // Setup Controller
    controller = await Controller.new(
        vat.address,
        pot.address,
        treasury.address,
        { from: owner },
    );
    treasury.orchestrate(controller.address, { from: owner });

    // Setup yDai
    const block = await web3.eth.getBlockNumber();
    maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
    yDai1 = await newYdai(maturity1, "Name1", "Symbol1")
    controller.addSeries(yDai1.address, { from: owner });
    yDai1.orchestrate(controller.address, { from: owner });
    treasury.orchestrate(yDai1.address, { from: owner });

    maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
    yDai2 = await newYdai(maturity2, "Name2", "Symbol2")
    controller.addSeries(yDai2.address, { from: owner });
    yDai2.orchestrate(controller.address, { from: owner });
    treasury.orchestrate(yDai2.address, { from: owner });

    return {
        controller,
        yDai1,
        maturity1,
        yDai2,
        maturity2,

    }
}

module.exports = {
    setupYield,
    newYdai,
    setupYdaiController,
}
