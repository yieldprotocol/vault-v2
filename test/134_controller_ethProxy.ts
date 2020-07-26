// Peripheral
const EthProxy = artifacts.require('EthProxy');

// @ts-ignore
import helper  from 'ganache-time-traveler';
// @ts-ignore
import { balance } from '@openzeppelin/test-helpers';
import { WETH, daiTokens1, wethTokens1 } from './shared/utils';
import { Contract, YieldEnvironmentLite, MakerEnvironment } from "./shared/fixtures";

contract('Controller - EthProxy', async (accounts) =>  {
    let [ owner, user ] = accounts;

    let snapshot: any;
    let snapshotId: string;
    let maker: MakerEnvironment;

    let dai: Contract;
    let vat: Contract;
    let pot: Contract;
    let controller: Contract;
    let yDai1: Contract;
    let chai: Contract;
    let treasury: Contract;
    let ethProxy: Contract;
    let weth: Contract;

    let maturity1: number;
    let maturity2: number;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        const env = await YieldEnvironmentLite.setup();
        maker = env.maker;
        controller = env.controller;
        treasury = env.treasury;
        pot = env.maker.pot;
        vat = env.maker.vat;
        dai = env.maker.dai;
        chai = env.maker.chai;
        weth = env.maker.weth;

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await env.newYDai(maturity1, "Name", "Symbol");
        await env.newYDai(maturity2, "Name", "Symbol");

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
        await ethProxy.post(wethTokens1, { from: owner, value: wethTokens1 });

        // @ts-ignore
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

    describe("with posted eth", () => {
        beforeEach(async() => {
            await ethProxy.post(wethTokens1, { from: owner, value: wethTokens1 });

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
            await ethProxy.withdraw(wethTokens1, { from: owner });

            // @ts-ignore
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
    });
});
