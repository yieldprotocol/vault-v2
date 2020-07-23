// Peripheral
const EthProxy = artifacts.require('EthProxy');

const helper = require('ganache-time-traveler');
const { balance } = require('@openzeppelin/test-helpers');
const { WETH, daiTokens1, wethTokens1 } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai } = require("./shared/fixtures");

contract('Controller - EthProxy', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;
    let ethProxy;

    let snapshot;
    let snapshotId;

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

        // Setup EthProxy
        ethProxy = await EthProxy.new(
            weth.address,
            treasury.address,
            controller.address,
            { from: owner },
        );
        await controller.addDelegate(ethProxy.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("allows user to post eth", async() => {
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            0,
            "Treasury has weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf.call(WETH, owner),
            0,
            "Owner has borrowing power",
        );
        
        const previousBalance = await balance.current(owner);
        await ethProxy.post(owner, owner, wethTokens1, { from: owner, value: wethTokens1 });

        expect(await balance.current(owner)).to.be.bignumber.lt(previousBalance);
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            wethTokens1.toString(),
            "Treasury should have weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf.call(WETH, owner),
            daiTokens1.toString(),
            "Owner should have " + daiTokens1 + " borrowing power, instead has " + await controller.powerOf.call(WETH, owner),
        );
    });

    it("allows user to post eth to a different account", async() => {
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            0,
            "Treasury has weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf.call(WETH, user),
            0,
            "User has borrowing power",
        );
        
        const previousBalance = await balance.current(owner);
        await ethProxy.post(owner, user, wethTokens1, { from: owner, value: wethTokens1 });

        expect(await balance.current(owner)).to.be.bignumber.lt(previousBalance);
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            wethTokens1.toString(),
            "Treasury should have weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf.call(WETH, user),
            daiTokens1.toString(),
            "User should have " + daiTokens1 + " borrowing power, instead has " + await controller.powerOf.call(WETH, user),
        );
    });

    describe("with posted eth", () => {
        beforeEach(async() => {
            await ethProxy.post(owner, owner, wethTokens1, { from: owner, value: wethTokens1 });

            assert.equal(
                (await vat.urns(WETH, treasury.address)).ink,
                wethTokens1.toString(),
                "Treasury does not have weth in MakerDAO",
            );
            assert.equal(
                await controller.powerOf.call(WETH, owner),
                daiTokens1.toString(),
                "Owner does not have borrowing power",
            );
            assert.equal(
                await weth.balanceOf(owner),
                0,
                "Owner has collateral in hand"
            );
            assert.equal(
                await yDai1.balanceOf(owner),
                0,
                "Owner has yDai",
            );
            assert.equal(
                await controller.debtDai.call(WETH, maturity1, owner),
                0,
                "Owner has debt",
            );
        });

        it("allows user to withdraw weth", async() => {
            const previousBalance = await balance.current(owner);
            await ethProxy.withdraw(owner, owner, wethTokens1, { from: owner });

            expect(await balance.current(owner)).to.be.bignumber.gt(previousBalance);
            assert.equal(
                (await vat.urns(WETH, treasury.address)).ink,
                0,
                "Treasury should not not have weth in MakerDAO",
            );
            assert.equal(
                await controller.powerOf.call(WETH, owner),
                0,
                "Owner should not have borrowing power",
            );
        });

        it("allows user to withdraw weth to another account", async() => {
            const previousBalance = await balance.current(user);
            await ethProxy.withdraw(owner, user, wethTokens1, { from: owner });

            expect(await balance.current(user)).to.be.bignumber.gt(previousBalance);
            assert.equal(
                (await vat.urns(WETH, treasury.address)).ink,
                0,
                "Treasury should not not have weth in MakerDAO",
            );
            assert.equal(
                await controller.powerOf.call(WETH, owner),
                0,
                "Owner should not have borrowing power",
            );
        });
    });
});