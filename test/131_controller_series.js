const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { YieldEnvironmentLite } = require("./shared/fixtures");

contract('Controller: Multi-Series', async (accounts) =>  {
    let [ owner ] = accounts;
    const THREE_MONTHS = 7776000;

    let snapshot;
    let snapshotId;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        const yield = await YieldEnvironmentLite.setup();
        controller = yield.controller;
        weth = yield.maker.weth;
        pot = yield.maker.pot;
        vat = yield.maker.vat;
        dai = yield.maker.dai;

        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await yield.newYDai(maturity1, "Name", "Symbol", true);

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await yield.newYDai(maturity2, "Name", "Symbol", true);
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
            "Controller should contain " + (await yDai1.name()),
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
            "Controller should contain " + (await yDai1.name()),
        );
        assert.equal(
            await controller.containsSeries(maturity2),
            true,
            "Controller should contain " + (await yDai2.name()),
        );
        assert.equal(
            await controller.series(maturity1),
            yDai1.address,
            "Controller should have the contract for " + (await yDai1.name()),
        );
        assert.equal(
            await controller.series(maturity2),
            yDai2.address,
            "Controller should have the contract for " + (await yDai2.name()),
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
