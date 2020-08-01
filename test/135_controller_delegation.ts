// @ts-ignore
import helper from 'ganache-time-traveler';
// @ts-ignore
import { BN, expectRevert } from '@openzeppelin/test-helpers';
import { WETH, rate1, daiTokens1, wethTokens1, toRay, mulRay, divRay, divrupRay, addBN, subBN } from './shared/utils';
import { MakerEnvironment, YieldEnvironmentLite, Contract } from "./shared/fixtures";
import { BigNumber } from 'ethers'

contract('Controller - Delegation', async (accounts) =>  {
    let [ owner, user1, user2, user3 ] = accounts;

    let snapshot: any;
    let snapshotId: string;
    let maker: MakerEnvironment;

    let weth: Contract;
    let dai: Contract;
    let vat: Contract;
    let pot: Contract;
    let treasury: Contract;
    let controller: Contract;
    let yDai1: Contract;
    let yDai2: Contract;

    let maturity1: number;
    let maturity2: number;

    beforeEach(async() => {
        snapshot = await helper.takeSnapshot();
        snapshotId = snapshot['result'];

        const env = await YieldEnvironmentLite.setup();
        maker = env.maker;
        controller = env.controller;
        treasury = env.treasury;
        weth = env.maker.weth;
        pot = env.maker.pot;
        vat = env.maker.vat;
        dai = env.maker.dai;

        // Setup yDai
        const block = await web3.eth.getBlockNumber();
        maturity1 = (await web3.eth.getBlock(block)).timestamp + 1000;
        maturity2 = (await web3.eth.getBlock(block)).timestamp + 2000;
        yDai1 = await env.newYDai(maturity1, "Name", "Symbol");
        yDai2 = await env.newYDai(maturity2, "Name", "Symbol");
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });

    it("doesn't allow to post from others if not a delegate", async() => {
        await expectRevert(
            controller.post(WETH, user1, user2, daiTokens1, { from: user2 }),
            "Controller: Only Holder Or Delegate",
        );
    });

    it("allows delegates to post weth from others", async() => {
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            0,
            "Treasury has weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf(WETH, user1),
            0,
            "User1 has borrowing power",
        );
        
        await weth.deposit({ from: user1, value: wethTokens1 });
        await controller.addDelegate(user2, { from: user1 });
        await weth.approve(treasury.address, wethTokens1, { from: user1 }); 
        const event = (await controller.post(WETH, user1, user2, wethTokens1, { from: user2 })).logs[0];
        
        assert.equal(
            event.event,
            "Posted",
        );
        assert.equal(
            bytes32ToString(event.args.collateral),
            bytes32ToString(WETH),
        );
        assert.equal(
            event.args.user,
            user2,
        );
        assert.equal(
            event.args.amount,
            wethTokens1.toString(),
        );
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            wethTokens1.toString(),
            "Treasury should have weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf(WETH, user2),
            daiTokens1.toString(),
            "User2 should have " + daiTokens1 + " borrowing power, instead has " + await controller.powerOf(WETH, user2),
        );
        assert.equal(
            await controller.posted(WETH, user2),
            wethTokens1.toString(),
            "User2 should have " + wethTokens1 + " weth posted, instead has " + await controller.posted(WETH, user2),
        );
    });

    describe("with posted weth", () => {
        beforeEach(async() => {
            await weth.deposit({ from: user1, value: wethTokens1 });
            await weth.approve(treasury.address, wethTokens1, { from: user1 }); 
            await controller.post(WETH, user1, user1, wethTokens1, { from: user1 });

            await weth.deposit({ from: user2, value: wethTokens1 });
            await weth.approve(treasury.address, wethTokens1, { from: user2 }); 
            await controller.post(WETH, user2, user2, wethTokens1, { from: user2 });
        });

        // TODO: Test delegation on `withdraw`

        it("doesn't allow to borrow yDai from others if not a delegate", async() => {
            await expectRevert(
                controller.borrow(WETH, maturity1, user1, user2, daiTokens1, { from: user2 }),
                "Controller: Only Holder Or Delegate",
            );
        });

        it("allows to borrow yDai from others", async() => {
            await controller.addDelegate(user2, { from: user1 })
            const event: any = (await controller.borrow(WETH, maturity1, user1, user2, daiTokens1, { from: user2 })).logs[0];

            assert.equal(
                event.event,
                "Borrowed",
            );
            assert.equal(
                bytes32ToString(event.args.collateral),
                bytes32ToString(WETH),
            );
            assert.equal(
                event.args.maturity,
                maturity1,
            );
            assert.equal(
                event.args.user,
                user1,
            );
            assert.equal(
                event.args.amount,
                daiTokens1.toString(), // This is actually a yDai amount
            );
            assert.equal(
                await yDai1.balanceOf(user2),
                daiTokens1.toString(),
                "User2 should have yDai",
            );
            assert.equal(
                await controller.debtDai(WETH, maturity1, user1),
                daiTokens1.toString(),
                "User1 should have debt",
            );
        });

        it("allows to borrow yDai from others, for others", async() => {
            await controller.addDelegate(user2, { from: user1 })
            const event: any = (await controller.borrow(WETH, maturity1, user1, user3, daiTokens1, { from: user2 })).logs[0];

            assert.equal(
                event.event,
                "Borrowed",
            );
            assert.equal(
                bytes32ToString(event.args.collateral),
                bytes32ToString(WETH),
            );
            assert.equal(
                event.args.maturity,
                maturity1,
            );
            assert.equal(
                event.args.user,
                user1,
            );
            assert.equal(
                event.args.amount,
                daiTokens1.toString(), // This is actually a yDai amount
            );
            assert.equal(
                await yDai1.balanceOf(user3),
                daiTokens1.toString(),
                "User3 should have yDai",
            );
            assert.equal(
                await controller.debtDai(WETH, maturity1, user1),
                daiTokens1.toString(),
                "User1 should have debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await controller.borrow(WETH, maturity1, user1, user1, daiTokens1, { from: user1 });
                await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 });
            });

            describe("with borrowed yDai from two series", () => {
                beforeEach(async() => {
                    await weth.deposit({ from: user1, value: wethTokens1 });
                    await weth.approve(treasury.address, wethTokens1, { from: user1 }); 
                    await controller.post(WETH, user1, user1, wethTokens1, { from: user1 });
                    await controller.borrow(WETH, maturity2, user1, user1, daiTokens1, { from: user1 });

                    await weth.deposit({ from: user2, value: wethTokens1 });
                    await weth.approve(treasury.address, wethTokens1, { from: user2 }); 
                    await controller.post(WETH, user2, user2, wethTokens1, { from: user2 });
                    await controller.borrow(WETH, maturity2, user2, user2, daiTokens1, { from: user2 });
                });

                it("others need to be added as delegates to repay yDai with others' funds", async() => {
                    await expectRevert(
                        controller.repayYDai(WETH, maturity1, user1, user1, daiTokens1, { from: user2 }),
                        "Controller: Only Holder Or Delegate",
                    );
                });

                it("allows delegates to use funds to repay yDai debts", async() => {
                    await controller.addDelegate(user2, { from: user1 });
                    await yDai1.approve(treasury.address, daiTokens1, { from: user1 });
                    const event = (await controller.repayYDai(WETH, maturity1, user1, user1, daiTokens1, { from: user2 })).logs[0];
        
                    assert.equal(
                        event.event,
                        "Borrowed",
                    );
                    assert.equal(
                        bytes32ToString(event.args.collateral),
                        bytes32ToString(WETH),
                    );
                    assert.equal(
                        event.args.maturity,
                        maturity1,
                    );
                    assert.equal(
                        event.args.user,
                        user1,
                    );
                    assert.equal(
                        event.args.amount,
                        daiTokens1.mul(-1).toString(), // This is actually a yDai amount
                    );
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        0,
                        "User1 should not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                });

                it("delegates are allowed to use fund to pay debts of any user", async() => {
                    await controller.addDelegate(user2, { from: user1 });
                    await yDai1.approve(treasury.address, daiTokens1, { from: user1 });
                    const event = (await controller.repayYDai(WETH, maturity1, user1, user2, daiTokens1, { from: user2 })).logs[0];
        
                    assert.equal(
                        event.event,
                        "Borrowed",
                    );
                    assert.equal(
                        bytes32ToString(event.args.collateral),
                        bytes32ToString(WETH),
                    );
                    assert.equal(
                        event.args.maturity,
                        maturity1,
                    );
                    assert.equal(
                        event.args.user,
                        user2,
                    );
                    assert.equal(
                        event.args.amount,
                        daiTokens1.mul(-1).toString(), // This is actually a yDai amount
                    );
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        0,
                        "User1 should not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai(WETH, maturity1, user2),
                        0,
                        "User2 should not have debt",
                    );
                });

                it("others need to be added as delegates to repay dai with others' funds", async() => {
                    await expectRevert(
                        controller.repayDai(WETH, maturity1, user1, user1, daiTokens1, { from: user2 }),
                        "Controller: Only Holder Or Delegate",
                    );
                });

                it("allows delegates to use funds to repay dai debts", async() => {
                    await maker.getDai(user1, daiTokens1, rate1);
                    await controller.addDelegate(user2, { from: user1 });
                    await dai.approve(treasury.address, daiTokens1, { from: user1 });
                    const event = (await controller.repayDai(WETH, maturity1, user1, user1, daiTokens1, { from: user2 })).logs[0];
        
                    assert.equal(
                        event.event,
                        "Borrowed",
                    );
                    assert.equal(
                        bytes32ToString(event.args.collateral),
                        bytes32ToString(WETH),
                    );
                    assert.equal(
                        event.args.maturity,
                        maturity1,
                    );
                    assert.equal(
                        event.args.user,
                        user1,
                    );
                    assert.equal(
                        event.args.amount,
                        daiTokens1.mul(-1).toString(), // This is actually a yDai amount
                    );
                    assert.equal(
                        await dai.balanceOf(user1),
                        0,
                        "User1 should not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                });

                it("delegates are allowed to use dai funds to pay debts of any user", async() => {
                    await controller.addDelegate(user2, { from: user1 });
                    await maker.getDai(user1, daiTokens1, rate1);
                    await dai.approve(treasury.address, daiTokens1, { from: user1 });
                    const event = (await controller.repayDai(WETH, maturity1, user1, user2, daiTokens1, { from: user2 })).logs[0];
        
                    assert.equal(
                        event.event,
                        "Borrowed",
                    );
                    assert.equal(
                        bytes32ToString(event.args.collateral),
                        bytes32ToString(WETH),
                    );
                    assert.equal(
                        event.args.maturity,
                        maturity1,
                    );
                    assert.equal(
                        event.args.user,
                        user2,
                    );
                    assert.equal(
                        event.args.amount,
                        daiTokens1.mul(-1).toString(), // This is actually a yDai amount
                    );
                    assert.equal(
                        await dai.balanceOf(user1),
                        0,
                        "User1 should not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai(WETH, maturity1, user2),
                        0,
                        "User2 should not have debt",
                    );
                });
            });
        });
    });
});

function bytes32ToString(text: string) {
    return web3.utils.toAscii(text).replace(/\0/g, '');
}
