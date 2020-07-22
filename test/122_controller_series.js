// YDai
const YDai = artifacts.require('YDai');

const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');

const { setupMaker, newTreasury, newController } = require("./shared/fixtures");

contract('Controller: Multi-Series', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let jug;
    let pot;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;

    const THREE_MONTHS = 7776000;

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

        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity1,
            "Name",
            "Symbol",
        );

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await YDai.new(
            vat.address,
            jug.address,
            pot.address,
            treasury.address,
            maturity2,
            "Name",
            "Symbol",
        );
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("adds series", async() => {
        assert.equal(
            await controller.containsSeries(maturity1),
            false,
            "Controller should not contain any maturity",
        );

        await controller.addSeries(yDai1.address, { from: owner });

        assert.equal(
            await controller.containsSeries(maturity1),
            true,
            "Controller should contain " + (await yDai1.name.call()),
        );

        assert.equal(
            await controller.skimStart(),
            maturity1 + THREE_MONTHS
        );
    });

    it("adds several series", async() => {
        await controller.addSeries(yDai1.address, { from: owner });
        await controller.addSeries(yDai2.address, { from: owner });

        assert.equal(
            await controller.containsSeries(maturity1),
            true,
            "Controller should contain " + (await yDai1.name.call()),
        );
        assert.equal(
            await controller.containsSeries(maturity2),
            true,
            "Controller should contain " + (await yDai2.name.call()),
        );
        assert.equal(
            await controller.series(maturity1),
            yDai1.address,
            "Controller should have the contract for " + (await yDai1.name.call()),
        );
        assert.equal(
            await controller.series(maturity2),
            yDai2.address,
            "Controller should have the contract for " + (await yDai2.name.call()),
        );
        assert.equal(
            await controller.skimStart(),
            maturity2 + THREE_MONTHS
        );
    });

    it("can't add same series twice", async() => {
        await controller.addSeries(yDai1.address, { from: owner });
        await expectRevert(
            controller.addSeries(yDai1.address, { from: owner }),
            "Controller: Series already added",
        );
    });
});
