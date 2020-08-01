// @ts-ignore
import helper from 'ganache-time-traveler';
// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers';
import { YieldEnvironmentLite, Contract } from "./shared/fixtures";

contract('Controller: Multi-Series', async (accounts) =>  {
    let [ owner ] = accounts;
    const THREE_MONTHS = 7776000;

    let snapshot: any;
    let snapshotId: string;

    let weth: Contract;
    let dai: Contract;
    let vat: Contract;
    let pot: Contract;
    let controller: Contract;
    let yDai1: Contract;
    let yDai2: Contract;

    let maturity1: number;
    let maturity2: number;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        const env = await YieldEnvironmentLite.setup();
        controller = env.controller;
        weth = env.maker.weth;
        pot = env.maker.pot;
        vat = env.maker.vat;
        dai = env.maker.dai;

        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        yDai1 = await env.newYDai(maturity1, "Name", "Symbol", true);

        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai2 = await env.newYDai(maturity2, "Name", "Symbol", true);
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
    });

    it("can't add same series twice", async() => {
        await controller.addSeries(yDai1.address, { from: owner });
        await expectRevert(
            controller.addSeries(yDai1.address, { from: owner }),
            "Controller: Series already added",
        );
    });
});
