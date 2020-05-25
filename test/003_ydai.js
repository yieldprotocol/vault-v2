const YDai = artifacts.require('YDai');
const Pot = artifacts.require('Pot');
const Vat = artifacts.require('Vat');
const helper = require('ganache-time-traveler');

const truffleAssert = require('truffle-assertions');
const { expectRevert } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let yDai;
    let maturity;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    let snapshot;
    let snapshotId;
    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    const originalChi  = "1300000000000000000000000000";        // 1.3
    const finalChi  = "1820000000000000000000000000";           // 1.82
    const chiDifferential  = "1400000000000000000000000000";    // 1.4 = 1.82 / 1.3
    const originalRate  = "1200000000000000000000000000";       // 1.2
    const rateIncrease  = "300000000000000000000000000";        // 0.3
    const rateDifferential  = "12500000000000000000000000000";  // 1.25 = 1.5 / 1.2
    // console.log(limits);


    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?
        await vat.rely(vat.address, { from: owner });
        // Set rate to 1.2
        await vat.fold(ilk, vat.address, "200000000000000000000000000", { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Set chi to 1.3
        await pot.setChi(originalChi, { from: owner });

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
            originalChi,
            "chi not initialized",
        );
        assert(
            await yDai.rate(),
            originalRate,
            "rate not initialized",
        );
        assert(
            await yDai.maturity(),
            maturity,
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
            await pot.setChi(finalChi, { from: owner });
            assert(
                await yDai.chi.call(),
                chiDifferential,
                "Chi differential should be " + chiDifferential,
            );
        });

        it("yDai rate gets fixed at maturity time", async() => {
            await yDai.mature();
            await vat.fold(ilk, vat.address, rateIncrease, { from: owner });
            assert(
                await yDai.rate(),
                rateDifferential,
                "Rate differential should be " + rateDifferential,
            );
        });
    });
});