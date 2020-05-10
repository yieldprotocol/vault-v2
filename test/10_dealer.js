const Dealer = artifacts.require('Dealer');
const TestERC20 = artifacts.require('TestERC20');
const TestOracle = artifacts.require('TestOracle');
const YDai = artifacts.require('YDai');
const Pot = artifacts.require('Pot');
const Vat = artifacts.require('Vat');
const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');

contract('yDai', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let pot;
    let yDai;
    let oracle;
    let token;
    let dealer;
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

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Do we need to set the dsr to something different than one?

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(vat.address, pot.address, maturity, "Name", "Symbol");

        // Setup Collateral Token
        token = await TestERC20.new(0, { from: owner }); 

        // Setup Oracle
        oracle = await TestOracle.new({ from: owner });
        await oracle.setPrice(RAY); // Setting price at 1

        // Setup Dealer
        dealer = await Dealer.new(yDai.address, token.address, oracle.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("should setup yDai", async() => {
        assert(
            (await yDai.chi()) == RAY,
            "chi not initialized",
        );
        assert(
            (await yDai.rate()) == RAY,
            "rate not initialized",
        );
        assert(
            (await yDai.maturity()) == maturity,
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
        await truffleAssert.fails(
            yDai.mature(),
            truffleAssert.REVERT,
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

    describe("once mature", () => {
        beforeEach(async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai.mature();
        });

        // TODO: Test with a moving chi
        it("chi gets fixed to maturity time", async() => {
            assert((await yDai.chi()) == RAY);
        });

        // TODO: Test with a moving rate
        it("rate gets fixed to maturity time", async() => {
            assert((await yDai.rate()) == RAY);
        });
    });
});