// External
const { setupMaker, newTreasury, newYDai, newController } = require("./shared/fixtures");

// YDai
const YDai = artifacts.require('YDai');

// Mocks
const FlashMinterMock = artifacts.require('FlashMinterMock');

const helper = require('ganache-time-traveler');
const { WETH, chi1, rate1, daiTokens1, wethTokens1, toRay, mulRay, divRay, subBN } = require('./shared/utils');
const { expectEvent, expectRevert } = require('@openzeppelin/test-helpers');

contract('yDai', async (accounts) =>  {
    let [ owner, user1, other ] = accounts;
    let vat;
    let weth;
    let dai;
    let jug;
    let pot;
    let treasury;
    let yDai1;
    let flashMinter;

    const rate2 = toRay(1.82);
    const chi2 = toRay(1.5);

    const chiDifferential  = divRay(chi2, chi1);

    const daiTokens2 = mulRay(daiTokens1, chiDifferential);
    const wethTokens2 = mulRay(wethTokens1, chiDifferential)

    let maturity;

    let snapshot;
    let snapshotId;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        ({
            vat,
            weth,
            wethJoin,
            dai,
            daiJoin,
            pot,
            jug,
            chai
        } = await setupMaker());
        treasury = await newTreasury();
        controller = await newController();

        // Setup yDai1
        const block = await web3.eth.getBlockNumber();
        maturity = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await newYDai(maturity, "Name", "Symbol");

        // Test setup
        // Setup Flash Minter
        flashMinter = await FlashMinterMock.new(
            { from: owner },
        );
        
        // Deposit some weth to treasury the sneaky way so that redeem can pull some dai
        await treasury.orchestrate(owner, { from: owner });
        await weth.deposit({ from: owner, value: wethTokens2.mul(2) });
        await weth.approve(treasury.address, wethTokens2.mul(2), { from: owner });
        await treasury.pushWeth(owner, wethTokens2.mul(2), { from: owner });

        // Mint some yDai1 the sneaky way, only difference is that the Controller doesn't record the user debt.
        await yDai1.orchestrate(owner, { from: owner });
        await yDai1.mint(user1, daiTokens1, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("should setup yDai1", async() => {
        assert(
            await yDai1.chiGrowth.call(),
            toRay(1.0).toString(),
            "chi not initialized",
        );
        assert(
            await yDai1.rateGrowth(),
            toRay(1.0).toString(),
            "rate not initialized",
        );
        assert(
            await yDai1.maturity(),
            maturity.toString(),
            "maturity not initialized",
        );
    });

    it("yDai1 is not mature before maturity", async() => {
        assert.equal(
            await yDai1.isMature(),
            false,
        );
    });

    it("yDai1 can't be redeemed before maturity time", async() => {
        await expectRevert(
            yDai1.redeem(user1, user1, daiTokens1, { from: user1 }),
            "YDai: yDai is not mature",
        );
    });

    it("yDai1 cannot mature before maturity time", async() => {
        await expectRevert(
            yDai1.mature(),
            "YDai: Too early to mature",
        );
    });

    it("yDai1 can mature at maturity time", async() => {
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai1.mature();
        assert.equal(
            await yDai1.isMature(),
            true,
        );
    });

    it("yDai flash mints", async() => {
        const yDaiSupply = await yDai1.totalSupply();
        expectEvent(
            await flashMinter.flashMint(yDai1.address, daiTokens1, web3.utils.fromAscii("DATA"), { from: user1 }),
            "Parameters",
            {
                user: flashMinter.address,
                amount: daiTokens1.toString(),
                data: web3.utils.fromAscii("DATA"),
            },
        );

        assert.equal(
            await flashMinter.flashBalance(),
            daiTokens1.toString(),
            "FlashMinter should have seen the tokens",
        );
        assert.equal(
            await yDai1.totalSupply(),
            yDaiSupply.toString(),
            "There should be no change in yDai supply",
        );
    });

    describe("once mature", () => {
        beforeEach(async() => {
            await helper.advanceTime(1000);
            await helper.advanceBlock();
            await yDai1.mature();
        });

        it("yDai1 can't mature more than once", async() => {
            await expectRevert(
                yDai1.mature(),
                "YDai: Already mature",
            );
        });

        it("yDai1 chi gets fixed at maturity time", async() => {
            await pot.setChi(chi2, { from: owner });
            
            assert(
                await yDai1.chiGrowth.call(),
                subBN(chi2, chi1).toString(),
                "Chi differential should be " + subBN(chi2, chi1),
            );
        });

        it("yDai1 rate gets fixed at maturity time", async() => {
            await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner });
            
            assert(
                await yDai1.rateGrowth(),
                subBN(rate2, rate1).toString(),
                "Rate differential should be " + subBN(rate2, rate1),
            );
        });

        it("chiGrowth always <= rateGrowth", async() => {
            await pot.setChi(chi2, { from: owner });

            assert(
                await yDai1.chiGrowth.call(),
                await yDai1.rateGrowth(),
                "Chi differential should be " + await yDai1.rateGrowth(),
            );
        });

        it("redeem burns yDai1 to return dai, pulls dai from Treasury", async() => {
            assert.equal(
                await yDai1.balanceOf(user1),
                daiTokens1.toString(),
                "User1 does not have yDai1",
            );
            assert.equal(
                await dai.balanceOf(user1),
                0,
                "User1 has dai",
            );

            await yDai1.approve(yDai1.address, daiTokens1, { from: user1 });
            await yDai1.redeem(user1, user1, daiTokens1, { from: user1 });
    
            assert.equal(
                await dai.balanceOf(user1),
                daiTokens1.toString(),
                "User1 should have dai",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                0,
                "User1 should not have yDai1",
            );
        });

        it("yDai can be redeemed in favour of others", async() => {
            assert.equal(
                await yDai1.balanceOf(user1),
                daiTokens1.toString(),
                "User1 does not have yDai1",
            );
            assert.equal(
                await dai.balanceOf(other),
                0,
                "Other has dai",
            );
    
            await yDai1.approve(yDai1.address, daiTokens1, { from: user1 });
            await yDai1.redeem(user1, other, daiTokens1, { from: user1 });
    
            assert.equal(
                await dai.balanceOf(other),
                daiTokens1.toString(),
                "Other should have dai",
            );
            assert.equal(
                await yDai1.balanceOf(user1),
                0,
                "User1 should not have yDai1",
            );
        });

        describe("once chi increases", () => {
            beforeEach(async() => {
                await vat.fold(WETH, vat.address, subBN(rate2, rate1), { from: owner }); // Keeping above chi
                await pot.setChi(chi2, { from: owner });

                assert(
                    await yDai1.chiGrowth.call(),
                    chiDifferential.toString(),
                    "chi differential should be " + chiDifferential + ", instead is " + (await yDai1.chiGrowth.call()),
                );
            });
    
            it("redeem with increased chi returns more dai", async() => {
                // Redeem `daiTokens1` yDai to obtain `daiTokens1` * `chiDifferential`

                assert.equal(
                    await yDai1.balanceOf(user1),
                    daiTokens1.toString(),
                    "User1 does not have yDai1",
                );
        
                await yDai1.approve(yDai1.address, daiTokens1, { from: user1 });
                await yDai1.redeem(user1, user1, daiTokens1, { from: user1 });
        
                assert.equal(
                    await dai.balanceOf(user1),
                    daiTokens2.toString(),
                    "User1 should have " + daiTokens2 + " dai, instead has " + (await dai.balanceOf(user1)),
                );
                assert.equal(
                    await yDai1.balanceOf(user1),
                    0,
                    "User2 should have no yDai left, instead has " + (await yDai1.balanceOf(user1)),
                );
            });
        });
    });
});
