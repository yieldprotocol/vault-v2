const YDai = artifacts.require('YDai');
const Vault = artifacts.require('Vault');
const TestOracle = artifacts.require('TestOracle');
const TestERC20 = artifacts.require('TestERC20');
const TestVat = artifacts.require('TestVat');
const TestPot = artifacts.require('TestPot');
//const MockContract = artifacts.require("./MockContract");
const helper = require('ganache-time-traveler');
const truffleAssert = require('truffle-assertions');
const ethers = require('ethers')
const utils = ethers.utils

const supply = web3.utils.toWei("1000");
const collateralToPost = web3.utils.toWei("20");
const underlyingToLock = web3.utils.toWei("5");
const underlyingPrice = web3.utils.toWei("2");
const collateralRatio = web3.utils.toWei("2");
const user1collateral = web3.utils.toWei("100");
const user1underlying = web3.utils.toWei("100");
const rate      = "1019999142148527182676895718";
const laterRate = "1020000000000000000000000000";
const chi       = "1018008449363110619399951035";
const laterChi  = "1019000000000000000000000000";

contract('YDai', async (accounts) =>    {
    let yDai;
    let collateral;
    let vault;
    let underlying;
    let vat;
    let pot;
    let maturity;
    const [ owner, user1 ] = accounts;

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

        //current releases at: https://changelog.makerdao.com/
        vat = await TestVat.new();
        await vat.set(rate);
        pot = await TestPot.new();
        await pot.set(chi);

        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai = await YDai.new(
            underlying.address, 
            vault.address, 
            vat.address,
            pot.address,
            maturity
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


    describe('once users have borrowed yTokens', () => {
        beforeEach(async() => {
            await collateral.approve(vault.address, collateralToPost, { from: user1 });
            await vault.post(collateralToPost, { from: user1 });
    
            await yDai.borrow(underlyingToLock, { from: user1 });
        });

        it("before maturity, debt is static", async() => {
            assert.equal(
                await yDai.debtOf(user1),
                underlyingToLock,
            );
        });


        it("yToken is not mature before maturity", async() => {
            assert.equal(
                    await yDai.isMature.call(),
                    false,
            );
        });
    
        it("yToken cannot mature before maturity time", async() => {
                await truffleAssert.fails(
                    yDai.mature(),
                    truffleAssert.REVERT,
                    "YToken: Too early to mature",
                );
        });

        it("yToken can mature at maturity time", async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai.mature();
            assert.equal(
                await yDai.isMature.call(),
                true,
            );
        });

        it("yToken snapshots chi and rate", async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai.mature();
            assert.equal(
                await yDai.rate.call(),
                rate,
            );
            assert.equal(
                await yDai.chi.call(),
                chi,
            );
        });

        it("after maturity, debt grows with stability fee", async() => {
            //Get example rate: 
            // https://etherscan.io/address/0x35D1b3F3D7966A1DFe207aa4514C12a259A0492B#readContract
            // ilks -> 0x4554482d41000000000000000000000000000000000000000000000000000000
            // console.log(utils.formatBytes32String("ETH-A"))
            // console.log(utils.parseBytes32String( "0x4554482d41000000000000000000000000000000000000000000000000000000" ))
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai.mature();
            await vat.set(laterRate);
            result = await yDai.debtOf(user1);
            assert(
                result > web3.utils.toBN(underlyingToLock)
            );
        });
        
        /** 
        it("yToken can be redeemed for underlying", async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai.mature();
            await pot.set(laterChi);
            await yDai.redeem(underlyingToLock, { from: user1 });
            DaiBalance = await underlying.balanceOf(user1);
            yDaiBalance = await yDai.balanceOf(user1);
            console.log("Balance:", yDaiBalance.toString())
            console.log("underlyingToLock: ", underlyingToLock)
            assert.equal(
                    await underlying.balanceOf(user1),
                    user1underlying,
            );
        });
        */

    });

});