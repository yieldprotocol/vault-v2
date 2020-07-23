const helper = require('ganache-time-traveler');
const { expectRevert, expectEvent } = require('@openzeppelin/test-helpers');
const { WETH, daiTokens1, wethTokens1 } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai } = require("./shared/fixtures");

contract('yDai - Delegable', async (accounts) =>  {
    let [ owner, holder, other ] = accounts;
    let vat;
    let weth;
    let dai;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    
    let maturity1;
    let maturity2;

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

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await newYDai(maturity1, "Name", "Symbol");
        yDai2 = await newYDai(maturity2, "Name", "Symbol");

        // Post collateral to MakerDAO through Treasury
        await treasury.orchestrate(owner, { from: owner });
        await weth.deposit({ from: owner, value: wethTokens1 });
        await weth.approve(treasury.address, wethTokens1, { from: owner });
        await treasury.pushWeth(owner, wethTokens1, { from: owner });
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            wethTokens1.toString(),
        );

        // Mint some yDai the sneaky way
        await yDai1.orchestrate(owner, { from: owner });
        await yDai1.mint(holder, daiTokens1, { from: owner });

        // yDai matures
        await helper.advanceTime(1000);
        await helper.advanceBlock();
        await yDai1.mature();

        assert.equal(
            await yDai1.balanceOf(holder),
            daiTokens1.toString(),
            "Holder does not have yDai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has no savings",
        );
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("redeem is allowed for account holder", async() => {
        await yDai1.approve(yDai1.address, daiTokens1, { from: holder });
        await yDai1.redeem(holder, holder, daiTokens1, { from: holder });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder should have dai",
        );
    });

    it("redeem is not allowed for non designated accounts", async() => {
        await yDai1.approve(yDai1.address, daiTokens1, { from: holder });
        await expectRevert(
            yDai1.redeem(holder, holder, daiTokens1, { from: other }),
            "YDai: Only Holder Or Delegate",
        );
    });

    it("redeem is allowed for delegates", async() => {
        await yDai1.approve(yDai1.address, daiTokens1, { from: holder });
        expectEvent(
            await yDai1.addDelegate(other, { from: holder }),
            "Delegate",
            {
                user: holder,
                delegate: other,
                enabled: true,
            },
        );
        await yDai1.redeem(holder, holder, daiTokens1, { from: other });

        assert.equal(
            await treasury.debt(),
            daiTokens1.toString(),
            "Treasury should have debt",
        );
        assert.equal(
            await dai.balanceOf(holder),
            daiTokens1.toString(),
            "Holder should have dai",
        );
    });

    describe("with delegates", async() => {
        beforeEach(async() => {
            await yDai1.addDelegate(other, { from: holder });
        });

        it("redeem is not allowed if delegation revoked", async() => {
            expectEvent(
                await yDai1.revokeDelegate(other, { from: holder }),
                "Delegate",
                {
                    user: holder,
                    delegate: other,
                    enabled: false,
                },
            );

            await expectRevert(
                yDai1.redeem(holder, holder, daiTokens1, { from: other }),
                "YDai: Only Holder Or Delegate",
            );
        });
    });
});