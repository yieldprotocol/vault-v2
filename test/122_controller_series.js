// YDai
const YDai = artifacts.require('YDai');
const Controller = artifacts.require('Controller');

const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');

const { setupYield, newYdai } = require("./shared/fixtures");

contract('Controller: Multi-Series', async (accounts) =>  {
    let [ owner ] = accounts;
    let vat;
    let jug;
    let pot;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;

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
            chai,
            treasury
        } = await setupYield(owner, owner))

        // Setup Controller
        controller = await Controller.new(
            vat.address,
            pot.address,
            treasury.address,
            { from: owner },
        );
        treasury.orchestrate(controller.address, { from: owner });
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("adds series", async() => {
        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        
        assert.equal(
            await controller.containsSeries(maturity1),
            false,
            "Controller should not contain any maturity",
        );

        yDai1 = await newYdai(maturity1, "Name1", "Symbol1");
        treasury.orchestrate(yDai1.address, { from: owner });

        await controller.addSeries(yDai1.address, { from: owner });
        yDai1.orchestrate(controller.address, { from: owner });

        assert.equal(
            await controller.containsSeries(maturity1),
            true,
            "Controller should contain " + (await yDai1.name.call()),
        );
    });

    it("adds several series", async() => {
        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await newYdai(maturity1, "Name1", "Symbol1");
        treasury.orchestrate(yDai1.address, { from: owner });

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await newYdai(maturity2, "Name2", "Symbol2");
        treasury.orchestrate(yDai2.address, { from: owner });

        await controller.addSeries(yDai1.address, { from: owner });
        yDai1.orchestrate(controller.address, { from: owner });
        await controller.addSeries(yDai2.address, { from: owner });
        yDai2.orchestrate(controller.address, { from: owner });

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
    });

    it("can't add same series twice", async() => {
        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await newYdai(maturity1, "Name1", "Symbol1");
        treasury.orchestrate(yDai1.address, { from: owner });

        await controller.addSeries(yDai1.address, { from: owner });
        yDai1.orchestrate(controller.address, { from: owner });
        await expectRevert(
            controller.addSeries(yDai1.address, { from: owner }),
            "Controller: Series already added",
        );
    });
});
