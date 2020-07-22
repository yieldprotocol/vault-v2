const helper = require('ganache-time-traveler');
const { BN, expectRevert } = require('@openzeppelin/test-helpers');
const { WETH, spot, rate1, daiTokens1, wethTokens1, toRay, mulRay, divRay, addBN, subBN } = require('./shared/utils');
const { setupMaker, newTreasury, newController, newYDai, getDai } = require("./shared/fixtures");

contract('Controller - Weth', async (accounts) =>  {
    let [ owner, user1, user2, user3 ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let treasury;
    let yDai1;
    let yDai2;
    let controller;

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
    });

    afterEach(async() => {
        await helper.revertToSnapshot(snapshotId);
    });
    
    it("get the size of the contract", async() => {
        console.log();
        console.log("    ·--------------------|------------------|------------------|------------------·");
        console.log("    |  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("    ·····················|··················|··················|···················");
        
        const bytecode = controller.constructor._json.bytecode;
        const deployed = controller.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "    |  " + (controller.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("    ·--------------------|------------------|------------------|------------------·");
        console.log();
    });

    it("it doesn't allow to post weth below dust level", async() => {
        await weth.deposit({ from: user1, value: 1 });
        await weth.approve(treasury.address, 1, { from: user1 }); 
        await expectRevert(
            controller.post(WETH, user1, user1, 1, { from: user1 }),
            "Controller: Below dust",
        );
    });

    it("allows users to post weth", async() => {
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            0,
            "Treasury has weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf.call(WETH, user1),
            0,
            "User1 has borrowing power",
        );
        
        await weth.deposit({ from: user1, value: wethTokens1 });
        await weth.approve(treasury.address, wethTokens1, { from: user1 }); 
        const event = (await controller.post(WETH, user1, user1, wethTokens1, { from: user1 })).logs[0];
        
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
            user1,
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
            await controller.powerOf.call(WETH, user1),
            daiTokens1.toString(),
            "User1 should have " + daiTokens1 + " borrowing power, instead has " + await controller.powerOf.call(WETH, user1),
        );
        assert.equal(
            await controller.posted(WETH, user1),
            wethTokens1.toString(),
            "User1 should have " + wethTokens1 + " weth posted, instead has " + await controller.posted(WETH, user1),
        );
    });

    it("allows users to post weth for others", async() => {
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            0,
            "Treasury has weth in MakerDAO",
        );
        assert.equal(
            await controller.powerOf.call(WETH, user1),
            0,
            "User1 has borrowing power",
        );
        
        await weth.deposit({ from: user1, value: wethTokens1 });
        await weth.approve(treasury.address, wethTokens1, { from: user1 }); 
        const event = (await controller.post(WETH, user1, user2, wethTokens1, { from: user1 })).logs[0];
        
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
            await controller.powerOf.call(WETH, user2),
            daiTokens1.toString(),
            "User2 should have " + daiTokens1 + " borrowing power, instead has " + await controller.powerOf.call(WETH, user2),
        );
        assert.equal(
            await controller.posted(WETH, user2),
            wethTokens1.toString(),
            "User2 should have " + wethTokens1 + " weth posted, instead has " + await controller.posted(WETH, user2),
        );
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
            await controller.powerOf.call(WETH, user1),
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
            await controller.powerOf.call(WETH, user2),
            daiTokens1.toString(),
            "User2 should have " + daiTokens1 + " borrowing power, instead has " + await controller.powerOf.call(WETH, user2),
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


        it("doesn't allow to withdraw weth and leave collateral under dust", async() => {
            // Repay maturity1 completely
            const posted = (await controller.posted(WETH, user1, { from: user1 })).toString();
            const toWithdraw = (new BN(posted)).sub(new BN('1000')).toString();

            await expectRevert(
                controller.withdraw(WETH, user1, user1, toWithdraw, { from: user1 }),
                "Controller: Below dust",
            );
        });

        it("allows users to withdraw weth", async() => {
            const event = (await controller.withdraw(WETH, user1, user1, wethTokens1, { from: user1 })).logs[0];

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
                user1,
            );
            assert.equal(
                event.args.amount,
                wethTokens1.mul(-1).toString(),
            );
            assert.equal(
                await weth.balanceOf(user1),
                wethTokens1.toString(),
                "User1 should have collateral in hand"
            );
            assert.equal(
                (await vat.urns(WETH, treasury.address)).ink,
                wethTokens1.toString(),
                "Treasury should have " + wethTokens1 + " weth in MakerDAO",
            );
            assert.equal(
                await controller.powerOf.call(WETH, user1),
                0,
                "User1 should not have borrowing power",
            );
        });

        it("allows to borrow yDai", async() => {
            event = (await controller.borrow(WETH, maturity1, user1, user1, daiTokens1, { from: user1 })).logs[0];

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
                await yDai1.balanceOf(user1),
                daiTokens1.toString(),
                "User1 should have yDai",
            );
            assert.equal(
                await controller.debtDai.call(WETH, maturity1, user1),
                daiTokens1.toString(),
                "User1 should have debt",
            );
            assert.equal(
                await controller.totalDebtYDai(WETH, maturity1),
                daiTokens1.toString(), // Dai == yDai before maturity
                "System should have debt",
            );
        });

        it("allows to borrow yDai for others", async() => {
            event = (await controller.borrow(WETH, maturity1, user1, user2, daiTokens1, { from: user1 })).logs[0];

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
                await controller.debtDai.call(WETH, maturity1, user1),
                daiTokens1.toString(),
                "User1 should have debt",
            );
            assert.equal(
                await controller.totalDebtYDai(WETH, maturity1),
                daiTokens1.toString(), // Dai == yDai before maturity
                "System should have debt",
            );
        });

        it("doesn't allow to borrow yDai from others if not a delegate", async() => {
            await expectRevert(
                controller.borrow(WETH, maturity1, user1, user2, daiTokens1, { from: user2 }),
                "Controller: Only Holder Or Delegate",
            );
        });

        it("allows to borrow yDai from others", async() => {
            await controller.addDelegate(user2, { from: user1 })
            event = (await controller.borrow(WETH, maturity1, user1, user2, daiTokens1, { from: user2 })).logs[0];

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
                await controller.debtDai.call(WETH, maturity1, user1),
                daiTokens1.toString(),
                "User1 should have debt",
            );
            assert.equal(
                await controller.totalDebtYDai(WETH, maturity1),
                daiTokens1.toString(), // Dai == yDai before maturity
                "System should have debt",
            );
        });

        it("allows to borrow yDai from others, for others", async() => {
            await controller.addDelegate(user2, { from: user1 })
            event = (await controller.borrow(WETH, maturity1, user1, user3, daiTokens1, { from: user2 })).logs[0];

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
                await controller.debtDai.call(WETH, maturity1, user1),
                daiTokens1.toString(),
                "User1 should have debt",
            );
            assert.equal(
                await controller.totalDebtYDai(WETH, maturity1),
                daiTokens1.toString(), // Dai == yDai before maturity
                "System should have debt",
            );
        });

        it("doesn't allow to borrow yDai beyond borrowing power", async() => {
            await expectRevert(
                controller.borrow(WETH, maturity1, user1, user1, addBN(daiTokens1, 1), { from: user1 }), // Borrow 1 wei beyond power
                "Controller: Too much debt",
            );
        });

        describe("with borrowed yDai", () => {
            beforeEach(async() => {
                await controller.borrow(WETH, maturity1, user1, user1, daiTokens1, { from: user1 });
                await controller.borrow(WETH, maturity1, user2, user2, daiTokens1, { from: user2 });
            });

            it("aggregates debt totals", async() => {
                assert.equal(
                    await controller.totalDebtYDai(WETH, maturity1),
                    daiTokens1.mul(2).toString(), // Dai == yDai before maturity
                    "System should have debt",
                );
            });

            it("allows to borrow from a second series", async() => {
                await weth.deposit({ from: user1, value: wethTokens1 });
                await weth.approve(treasury.address, wethTokens1, { from: user1 }); 
                await controller.post(WETH, user1, user1, wethTokens1, { from: user1 });
                await controller.borrow(WETH, maturity2, user1, user1, daiTokens1, { from: user1 });

                assert.equal(
                    await yDai1.balanceOf(user1),
                    daiTokens1.toString(),
                    "User1 should have yDai",
                );
                assert.equal(
                    await controller.debtDai.call(WETH, maturity1, user1),
                    daiTokens1.toString(),
                    "User1 should have debt for series 1",
                );
                assert.equal(
                    await yDai2.balanceOf(user1),
                    daiTokens1.toString(),
                    "User1 should have yDai2",
                );
                assert.equal(
                    await controller.debtDai.call(WETH, maturity2, user1),
                    daiTokens1.toString(),
                    "User1 should have debt for series 2",
                );
                assert.equal(
                    await controller.totalDebtDai.call(WETH, user1),
                    addBN(daiTokens1, daiTokens1).toString(),
                    "User1 should a combined debt",
                );
                assert.equal(
                    await controller.totalDebtYDai(WETH, maturity1),
                    daiTokens1.mul(2).toString(), // Dai == yDai before maturity
                    "System should have debt",
                );
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

                it("doesn't allow to withdraw and become undercollateralized", async() => {
                    await expectRevert(
                        controller.borrow(WETH, maturity1, user1, user1, wethTokens1, { from: user1 }),
                        "Controller: Too much debt",
                    );
                });
    
                it("allows to repay yDai", async() => {
                    await yDai1.approve(treasury.address, daiTokens1, { from: user1 });
                    const event = (await controller.repayYDai(WETH, maturity1, user1, user1, daiTokens1, { from: user1 })).logs[0];
        
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
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });

                it("allows to repay yDai for others with own funds", async() => {
                    await yDai1.approve(treasury.address, daiTokens1, { from: user2 });
                    const event = (await controller.repayYDai(WETH, maturity1, user2, user1, daiTokens1, { from: user2 })).logs[0];
        
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
                        await yDai1.balanceOf(user2),
                        0,
                        "User2 should not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
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
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
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
                        await controller.debtDai.call(WETH, maturity1, user2),
                        0,
                        "User2 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });

                it("allows to repay yDai with dai", async() => {
                    await getDai(user1, daiTokens1, rate1);
    
                    assert.equal(
                        await dai.balanceOf(user1),
                        daiTokens1.toString(),
                        "User1 does not have dai",
                    );
                    assert.equal(
                        await controller.debtDai.call(WETH, maturity1, user1),
                        daiTokens1.toString(),
                        "User1 does not have debt",
                    );
    
                    await dai.approve(treasury.address, daiTokens1, { from: user1 });
                    const event = (await controller.repayDai(WETH, maturity1, user1, user1, daiTokens1, { from: user1 })).logs[0];
        
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
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });

                it("allows to repay dai debt for others with own funds", async() => {
                    await getDai(user2, daiTokens1, rate1);
                    await dai.approve(treasury.address, daiTokens1, { from: user2 });
                    const event = (await controller.repayDai(WETH, maturity1, user2, user1, daiTokens1, { from: user2 })).logs[0];
        
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
                        await dai.balanceOf(user2),
                        0,
                        "User2 should not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });

                it("others need to be added as delegates to repay dai with others' funds", async() => {
                    await expectRevert(
                        controller.repayDai(WETH, maturity1, user1, user1, daiTokens1, { from: user2 }),
                        "Controller: Only Holder Or Delegate",
                    );
                });

                it("allows delegates to use funds to repay dai debts", async() => {
                    await getDai(user1, daiTokens1, rate1);
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
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });

                it("delegates are allowed to use dai funds to pay debts of any user", async() => {
                    await controller.addDelegate(user2, { from: user1 });
                    await getDai(user1, daiTokens1, rate1);
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
                        await controller.debtDai.call(WETH, maturity1, user2),
                        0,
                        "User2 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });

                it("when dai is provided in excess for repayment, only the necessary amount is taken", async() => {
                    // Mint some yDai the sneaky way
                    await yDai1.orchestrate(owner, { from: owner });
                    await yDai1.mint(user1, 1, { from: owner }); // 1 extra yDai wei
                    const yDaiTokens = addBN(daiTokens1, 1); // daiTokens1 + 1 wei
    
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        yDaiTokens.toString(),
                        "User1 does not have yDai",
                    );
                    assert.equal(
                        await controller.debtDai.call(WETH, maturity1, user1),
                        daiTokens1.toString(),
                        "User1 does not have debt",
                    );
    
                    await yDai1.approve(treasury.address, yDaiTokens, { from: user1 });
                    await controller.repayYDai(WETH, maturity1, user1, user1, yDaiTokens, { from: user1 });
        
                    assert.equal(
                        await yDai1.balanceOf(user1),
                        1,
                        "User1 should have yDai left",
                    );
                    assert.equal(
                        await controller.debtDai.call(WETH, maturity1, user1),
                        0,
                        "User1 should not have debt",
                    );
                    assert.equal(
                        await controller.totalDebtYDai(WETH, maturity1),
                        daiTokens1.toString(), // Dai == yDai before maturity. We borrowed twice this.
                        "System should have debt",
                    );
                });
    
                // Set rate to 1.5
                let rateIncrease;
                let rateDifferential;
                let increasedDebt;
                let debtIncrease;
                let rate2;

                describe("after maturity, with a rate increase", () => {
                    beforeEach(async() => {
                        // Set rate to 1.5
                        rateIncrease = toRay(0.25);
                        rateDifferential = divRay(rate1.add(rateIncrease), rate1);
                        rate2 = rate1.add(rateIncrease);
                        increasedDebt = addBN(mulRay(daiTokens1, rateDifferential), 1); // YDai.rateGrowth() rounds up.
                        debtIncrease = subBN(increasedDebt, daiTokens1);

                        assert.equal(
                            await yDai1.balanceOf(user1),
                            daiTokens1.toString(),
                            "User1 does not have yDai",
                        );
                        assert.equal(
                            await controller.debtDai.call(WETH, maturity1, user1),
                            daiTokens1.toString(),
                            "User1 does not have debt",
                        );
                        // yDai matures
                        await helper.advanceTime(1000);
                        await helper.advanceBlock();
                        await yDai1.mature();
    
                        await vat.fold(WETH, vat.address, rateIncrease, { from: owner });
                    });
    
                    it("as rate increases after maturity, so does the debt in when measured in dai", async() => {
                        assert.equal(
                            await controller.debtDai.call(WETH, maturity1, user1),
                            increasedDebt.toString(),
                            "User1 should have " + increasedDebt + " debt after the rate change, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });
        
                    it("as rate increases after maturity, the debt doesn't in when measured in yDai", async() => {
                        assert.equal(
                            await controller.debtYDai(WETH, maturity1, user1),
                            daiTokens1.toString(),
                            "User1 should have " + daiTokens1 + " debt after the rate change, instead has " + (await controller.debtYDai(WETH, maturity1, user1)),
                        );
                    });
     
                    it("borrowing from two series, dai debt is aggregated", async() => {
                        assert.equal(
                            await controller.totalDebtDai.call(WETH, user1),
                            addBN(increasedDebt, daiTokens1).toString(),
                            "User1 should have " + addBN(increasedDebt, daiTokens1) + " debt after the rate change, instead has " + (await controller.totalDebtDai.call(WETH, user1)),
                        );
                    });
    
                    // TODO: Test that when yDai is provided in excess for repayment, only the necessary amount is taken

                    it("the yDai required to repay doesn't change after maturity as rate increases", async() => {
                        await yDai1.approve(treasury.address, daiTokens1, { from: user1 });
                        await controller.repayYDai(WETH, maturity1, user1, user1, daiTokens1, { from: user1 });
            
                        assert.equal(
                            await yDai1.balanceOf(user1),
                            0,
                            "User1 should not have yDai",
                        );
                        assert.equal(
                            await controller.debtDai.call(WETH, maturity1, user1),
                            0,
                            "User1 should have no dai debt, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });

                    it("more Dai is required to repay after maturity as rate increases", async() => {
                        await getDai(user1, daiTokens1, rate2); // daiTokens1 is not going to be enough anymore
                        await dai.approve(treasury.address, daiTokens1, { from: user1 });
                        await controller.repayDai(WETH, maturity1, user1, user1, daiTokens1, { from: user1 });
            
                        assert.equal(
                            await controller.debtDai.call(WETH, maturity1, user1),
                            debtIncrease.toString(),
                            "User1 should have " + debtIncrease + " dai debt, instead has " + (await controller.debtDai.call(WETH, maturity1, user1)),
                        );
                    });
                });    
            });
        });
    });
});

function bytes32ToString(text) {
    return web3.utils.toAscii(text).replace(/\0/g, '');
}
