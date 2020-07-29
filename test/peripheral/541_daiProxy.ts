const Pool = artifacts.require('Pool');
const DaiProxy = artifacts.require('DaiProxy');

import { BigNumber, BigNumberish } from 'ethers';
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

            // Allow daiProxy to act for `user1`
            await pool.addDelegate(daiProxy.address, { from: user1 });
            await controller.addDelegate(daiProxy.address, { from: user1 });

            // Post some weth to controller to be able to borrow
            await weth.deposit({ from: user1, value: wethTokens1 });
            await weth.approve(treasury.address, wethTokens1, { from: user1 });
            await controller.post(WETH, user1, user1, wethTokens1, { from: user1 });

            // Give some yDai to user1
            await yDai1.mint(user1, yDaiTokens1, { from: owner });
        });

        it("borrows dai for maximum yDai", async() => { // borrowDaiForMaximumYDai
            const oneToken = toWad(1);

            await daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, to, yDaiTokens1, oneToken, { from: user1 });

            assert.equal(
                await dai.balanceOf(to),
                oneToken.toString(),
            );
        });

        it("doesn't borrow dai if limit exceeded", async() => { // borrowDaiForMaximumYDai
            await expectRevert(
                daiProxy.borrowDaiForMaximumYDai(WETH, maturity1, to, yDaiTokens1, daiTokens1, { from: user1 }),
                "DaiProxy: Too much yDai required",
            );
        });

        it("borrows minimum dai for yDai", async() => { // borrowMinimumDaiForYDai
            const oneToken = new BN(toWad(1).toString());

            await daiProxy.borrowMinimumDaiForYDai(WETH, maturity1, to, yDaiTokens1, oneToken, { from: user1 });

            expect(await dai.balanceOf(to)).to.be.bignumber.gt(oneToken);
        });

        it("doesn't borrow dai if limit not reached", async() => { // borrowMinimumDaiForYDai
            const oneToken = new BN(toWad(1).toString());

            await expectRevert(
                daiProxy.borrowMinimumDaiForYDai(WETH, maturity1, to, oneToken, daiTokens1, { from: user1 }),
                "DaiProxy: Not enough Dai obtained",
            );
        });

        describe("with extra yDai reserves", () => {
            beforeEach(async() => {
                // Set up the pool to allow buying yDai
                const additionalYDaiReserves = toWad(34.4);
                await yDai1.mint(operator, additionalYDaiReserves, { from: owner });
                await yDai1.approve(pool.address, additionalYDaiReserves, { from: operator });
                await pool.sellYDai(operator, operator, additionalYDaiReserves, { from: operator });

                // Create some yDai debt for `user1`
                await controller.borrow(WETH, maturity1, user1, user1, daiTokens1, { from: user1 });

                // Give some Dai to `user1`
                await env.maker.getDai(user1, daiTokens1, rate1);
            });

            it("repays minimum yDai debt with dai", async() => { // repayMinimumYDaiDebtForDai
                const oneYDai = toWad(1);
                const twoDai = toWad(2);
                const yDaiDebt = new BN(daiTokens1.toString());

                await dai.approve(pool.address, daiTokens1, { from: user1 });
                await daiProxy.repayMinimumYDaiDebtForDai(WETH, maturity1, to, oneYDai, twoDai, { from: user1 });

                expect(await controller.debtYDai(WETH, maturity1, to)).to.be.bignumber.lt(yDaiDebt);
            });

            it("doesn't repay debt if limit not reached", async() => { // repayMinimumYDaiDebtForDai
                const oneDai = toWad(1);
                const twoYDai = toWad(2);

                await dai.approve(pool.address, daiTokens1, { from: user1 });

                await expectRevert(
                    daiProxy.repayMinimumYDaiDebtForDai(WETH, maturity1, to, twoYDai, oneDai, { from: user1 }),
                    "DaiProxy: Not enough yDai debt repaid",
                );
            });

            /* it("repays yDai debt for maximum dai", async() => { // repayYDaiDebtForMaximumDai
                const oneToken = toWad(1);
                await env.maker.getDai(from, daiTokens1, rate1);

                await pool.addDelegate(daiProxy.address, { from: user1 });
                await dai.approve(pool.address, daiTokens1, { from: user1 });
                await daiProxy.buyYDai(from, to, oneToken, oneToken.mul(2), { from: user1 });

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

                await pool.addDelegate(daiProxy.address, { from: user1 });
                await dai.approve(pool.address, daiTokens1, { from: user1 });

                await expectRevert(
                    daiProxy.buyYDai(from, to, oneToken, oneToken.div(2), { from: user1 }),
                    "daiProxy: Limit exceeded",
                );
            });*/
        });
    });
});
