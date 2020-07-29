const Pool = artifacts.require('Pool');
const DaiProxy = artifacts.require('DaiProxy');

import { WETH, wethTokens1, toWad, toRay, mulRay } from '../shared/utils';
import { YieldEnvironmentLite, Contract } from "../shared/fixtures";
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers';
import { assert, expect } from 'chai';

contract('DaiProxy', async (accounts) =>  {
    let [ owner, user1, operator, from, to ] = accounts;

    // These values impact the pool results
    const rate1 = toRay(1.4);
    const daiDebt1 = toWad(96);
    const daiTokens1 = mulRay(daiDebt1, rate1);
    const yDaiTokens1 = daiTokens1;

    let maturity1: number;
    let vat: Contract;
    let pot: Contract;
    let weth: Contract;
    let dai: Contract;
    let treasury: Contract;
    let controller: Contract;
    let yDai1: Contract;
    let pool: Contract;
    let daiProxy: Contract;
    let env: YieldEnvironmentLite;

    beforeEach(async() => {
        env = await YieldEnvironmentLite.setup();
        vat = env.maker.vat;
        weth = env.maker.weth;
        dai = env.maker.dai;
        pot = env.maker.pot;
        treasury = env.treasury;
        controller = env.controller;

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 31556952; // One year
        yDai1 = await env.newYDai(maturity1, "Name", "Symbol");

        // Setup Pool
        pool = await Pool.new(
            dai.address,
            yDai1.address,
            "Name",
            "Symbol",
            { from: owner }
        );

        // Setup DaiProxy
        daiProxy = await DaiProxy.new(
            vat.address,
            dai.address,
            pot.address,
            yDai1.address,
            controller.address,
            pool.address,
            { from: owner }
        );
        

        // Test setup

        // Allow owner to mint yDai the sneaky way, without recording a debt in controller
        await yDai1.orchestrate(owner, { from: owner });

    });

    describe("with liquidity", () => {
        beforeEach(async() => {
            // Init pool
            const daiReserves = daiTokens1;
            await env.maker.getDai(user1, daiReserves, rate1);
            await dai.approve(pool.address, daiReserves, { from: user1 });
            await pool.init(daiReserves, { from: user1 });

            // Allow daiProxy to act for `from`
            await pool.addDelegate(daiProxy.address, { from: from });
            await controller.addDelegate(daiProxy.address, { from: from });

            // Post some weth to controller to be able to borrow
            await weth.deposit({ from: from, value: wethTokens1 });
            await weth.approve(treasury.address, wethTokens1, { from: from });
            await controller.post(WETH, from, from, wethTokens1, { from: from });
        });

        it("borrows dai for maximum yDai", async() => { // borrowDaiForMaximumYDai
            const oneToken = toWad(1);
            await yDai1.mint(from, yDaiTokens1, { from: owner });

            const yDaiPaid = await daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, to, yDaiTokens1, oneToken, { from: from });

            assert.equal(
                await dai.balanceOf(to),
                oneToken.toString(),
            );
        });

        it("doesn't borrow dai if limit exceeded", async() => { // borrowDaiForMaximumYDai
            await expectRevert(
                daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, to, yDaiTokens1, daiTokens1, { from: from }),
                "DaiProxy: Too much yDai required",
            );
        });

        /* it("borrows minimum dai for yDai", async() => { // borrowMinimumDaiForYDai
            const oneToken = toWad(1);
            await yDai1.mint(from, oneToken, { from: owner });

            await pool.addDelegate(daiProxy.address, { from: from });
            await yDai1.approve(pool.address, oneToken, { from: from });
            await daiProxy.sellYDai(from, to, oneToken, oneToken.div(2), { from: from });

            assert.equal(
                await yDai1.balanceOf(from),
                0,
                "'From' wallet should have no yDai tokens",
            );

            const expectedDaiOut = (new BN(oneToken.toString())).mul(new BN('99814')).div(new BN('100000')); // I just hate javascript
            const daiOut = new BN(await dai.balanceOf(to));
            expect(daiOut).to.be.bignumber.gt(expectedDaiOut.mul(new BN('9999')).div(new BN('10000')));
            expect(daiOut).to.be.bignumber.lt(expectedDaiOut.mul(new BN('10001')).div(new BN('10000')));
        });

        it("doesn't borrow dai if limit not reached", async() => { // borrowMinimumDaiForYDai
            const oneToken = toWad(1);
            await yDai1.mint(from, oneToken, { from: owner });

            await pool.addDelegate(daiProxy.address, { from: from });
            await yDai1.approve(pool.address, oneToken, { from: from });

            await expectRevert(
                daiProxy.sellYDai(from, to, oneToken, oneToken.mul(2), { from: from }),
                "daiProxy: Limit not reached",
            );
        });

        describe("with extra yDai reserves", () => {
            beforeEach(async() => {
                const additionalYDaiReserves = toWad(34.4);
                await yDai1.mint(operator, additionalYDaiReserves, { from: owner });
                await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator });
                await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator });
            });

            it("repays minimum yDai debt with dai", async() => { // repayMinimumYDaiDebtForDai
                const oneToken = toWad(1);
                await env.maker.getDai(from, daiTokens1, rate1);

                await pool.addDelegate(daiProxy.address, { from: from });
                await dai.approve(pool.address, oneToken, { from: from });
                await daiProxy.sellDai(from, to, oneToken, oneToken.div(2), { from: from });

                assert.equal(
                    await dai.balanceOf(from),
                    daiTokens1.sub(oneToken).toString(),
                    "'From' wallet should have " + daiTokens1.sub(oneToken) + " dai tokens",
                );

                const expectedYDaiOut = (new BN(oneToken.toString())).mul(new BN('1132')).div(new BN('1000')); // I just hate javascript
                const yDaiOut = new BN(await yDai1.balanceOf(to));
                // TODO: Test precision with 48 and 64 bits with this trade and reserve levels
                expect(yDaiOut).to.be.bignumber.gt(expectedYDaiOut.mul(new BN('999')).div(new BN('1000')));
                expect(yDaiOut).to.be.bignumber.lt(expectedYDaiOut.mul(new BN('1001')).div(new BN('1000')));
            });

            it("doesn't reapy debt if limit not reached", async() => { // repayMinimumYDaiDebtForDai
                const oneToken = toWad(1);
                await env.maker.getDai(from, daiTokens1, rate1);

                await pool.addDelegate(daiProxy.address, { from: from });
                await dai.approve(pool.address, oneToken, { from: from });

                await expectRevert(
                    daiProxy.sellDai(from, to, oneToken, oneToken.mul(2), { from: from }),
                    "daiProxy: Limit not reached",
                );
            });

            it("repays yDai debt for maximum dai", async() => { // repayYDaiDebtForMaximumDai
                const oneToken = toWad(1);
                await env.maker.getDai(from, daiTokens1, rate1);

                await pool.addDelegate(daiProxy.address, { from: from });
                await dai.approve(pool.address, daiTokens1, { from: from });
                await daiProxy.buyYDai(from, to, oneToken, oneToken.mul(2), { from: from });

                assert.equal(
                    await yDai1.balanceOf(to),
                    oneToken.toString(),
                    "'To' wallet should have 1 yDai token",
                );

                const expectedDaiIn = (new BN(oneToken.toString())).mul(new BN('8835')).div(new BN('10000')); // I just hate javascript
                const daiIn = (new BN(daiTokens1.toString())).sub(new BN(await dai.balanceOf(from)));
                expect(daiIn).to.be.bignumber.gt(expectedDaiIn.mul(new BN('9999')).div(new BN('10000')));
                expect(daiIn).to.be.bignumber.lt(expectedDaiIn.mul(new BN('10001')).div(new BN('10000')));
            });

            it("doesn't repay debt if limit exceeded", async() => { // repayYDaiDebtForMaximumDai
                const oneToken = toWad(1);
                await env.maker.getDai(from, daiTokens1, rate1);

                await pool.addDelegate(daiProxy.address, { from: from });
                await dai.approve(pool.address, daiTokens1, { from: from });

                await expectRevert(
                    daiProxy.buyYDai(from, to, oneToken, oneToken.div(2), { from: from }),
                    "daiProxy: Limit exceeded",
                );
            });
        }); */
    });
});
