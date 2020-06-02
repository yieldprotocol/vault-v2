const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require('WETH9');
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const YDai = artifacts.require('YDai');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let pot;
    let yDai;
    let maturity;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const limits =  toRad(10000);
    const spot = toRay(1.5);
    const rate1 = toRay(1.2);
    const chi1 = toRay(1.3);
    const rate2 = toRay(1.5);
    const chi2 = toRay(1.82);

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        // Set up vat, join and weth
        vat = await Vat.new();

        weth = await Weth.new({ from: owner });
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.fold(ilk, vat.address, subBN(rate1, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Setup pot
        pot = await Pot.new(vat.address);
        await pot.setChi(chi1, { from: owner });

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("should setup yDai", async() => {
        assert(
            await yDai.chi.call(),
            chi1.toString(),
            "chi not initialized",
        );
        assert(
            await yDai.rate(),
            rate1.toString(),
            "rate not initialized",
        );
        assert(
            await yDai.maturity(),
            maturity.toString(),
            "maturity not initialized",
        );
    });

    it("yDai is not mature before maturity", async() => {
        assert.equal(
            await yDai.isMature(),
            false,
        );
    });

    it("yDai cannot mature before maturity time", async() => {
        await expectRevert(
            yDai.mature(),
            "YDai: Too early to mature",
        );
    });

    it("yDai can mature at maturity time", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        assert.equal(
            await yDai.isMature(),
            true,
        );
    });

    it("yDai can't mature more than once", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai.mature();
        await expectRevert(
            yDai.mature(),
            "YDai: Already mature",
        );
    });

    describe("once mature", () => {
        beforeEach(async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
        });

        it("yDai chi gets fixed at maturity time", async() => {
            await yDai.mature();
            await pot.setChi(chi2, { from: owner });
            assert(
                await yDai.chi.call(),
                subBN(chi2, chi1).toString(),
                "Chi differential should be " + subBN(chi2, chi1),
            );
        });

        it("yDai rate gets fixed at maturity time", async() => {
            await yDai.mature();
            await vat.fold(ilk, vat.address, subBN(rate2, rate1), { from: owner });
            assert(
                await yDai.rate(),
                subBN(rate2, rate1).toString(),
                "Rate differential should be " + subBN(rate2, rate1),
            );
        });
    });
});