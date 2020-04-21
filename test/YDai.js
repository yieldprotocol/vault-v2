const YDai = artifacts.require('YDai');
const Vault = artifacts.require('Vault');
const TestOracle = artifacts.require('TestOracle');
const TestERC20 = artifacts.require('TestERC20');
const MockContract = artifacts.require("./MockContract");
const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');

const supply = web3.utils.toWei("1000");
const collateralToPost = web3.utils.toWei("20");
const underlyingToLock = web3.utils.toWei("5");
const underlyingPrice = web3.utils.toWei("2");
const collateralRatio = web3.utils.toWei("2");

contract('YDai', async (accounts) =>    {
    let yDai;
    let collateral;
    let vault;
    let underlying;
    let vat;
    let pot;
    let maturity;
    const [ owner, user1 ] = accounts;
    const user1collateral = web3.utils.toWei("100");
    const user1underlying = web3.utils.toWei("100");

    beforeEach(async() => {
        let snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        underlying = await TestERC20.new(supply, { from: owner });
        await underlying.transfer(user1, user1underlying, { from: owner });
        
        collateral = await TestERC20.new(supply, { from: owner });
        await collateral.transfer(user1, user1collateral, { from: owner });
        const oracle = await TestOracle.new({ from: owner });
        await oracle.set(underlyingPrice, { from: owner });
        vault = await Vault.new(collateral.address, oracle.address, collateralRatio);

        vat = await MockContract.new();
        pot = await MockContract.new();

        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(
            underlying.address, 
            vault.address, 
            maturity, 
            vat.address,
            pot.address
        );
        await vault.transferOwnership(yDai.address);
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("yDai should be initialized", async() => {
        assert.equal(
                await yDai.vat.call(),
                vat.address,
        );

        assert.equal(
                await yDai.pot.call(),
                pot.address,
        );
    });


});