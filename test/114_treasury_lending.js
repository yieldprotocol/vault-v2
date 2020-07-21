const { expectRevert } = require('@openzeppelin/test-helpers');
const { setupYield } = require("./shared/fixtures");
const {
    WETH,
    daiDebt,
    daiTokens,
    wethTokens,
    chaiTokens,
} = require ("./shared/utils");

contract('Treasury - Lending', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let chai;
    let treasury;

    beforeEach(async() => {
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
    });

    it("get the size of the contract", async() => {
        console.log();
        console.log("    ·--------------------|------------------|------------------|------------------·");
        console.log("    |  Contract          ·  Bytecode        ·  Deployed        ·  Constructor     |");
        console.log("    ·····················|··················|··················|···················");
        
        const bytecode = treasury.constructor._json.bytecode;
        const deployed = treasury.constructor._json.deployedBytecode;
        const sizeOfB  = bytecode.length / 2;
        const sizeOfD  = deployed.length / 2;
        const sizeOfC  = sizeOfB - sizeOfD;
        console.log(
            "    |  " + (treasury.constructor._json.contractName).padEnd(18, ' ') +
            "|" + ("" + sizeOfB).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfD).padStart(16, ' ') + "  " +
            "|" + ("" + sizeOfC).padStart(16, ' ') + "  |");
        console.log("    ·--------------------|------------------|------------------|------------------·");
        console.log();
    });
    
    it("should fail for failed weth transfers", async() => {
        // Let's check how WETH is implemented, maybe we can remove this one.
    });

    it("allows to post collateral", async() => {
        assert.equal(
            (await weth.balanceOf(wethJoin.address)),
            web3.utils.toWei("0")
        );
        
        await weth.deposit({ from: owner, value: wethTokens });
        await weth.approve(treasury.address, wethTokens, { from: owner });
        await treasury.pushWeth(owner, wethTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await weth.balanceOf(wethJoin.address),
            wethTokens.toString(),
        );

        // Test collateral registering via `frob`
        assert.equal(
            (await vat.urns(WETH, treasury.address)).ink,
            wethTokens.toString(),
        );
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens});
            await weth.approve(treasury.address, wethTokens, { from: owner });
            await treasury.pushWeth(owner, wethTokens, { from: owner });
        });

        it("returns borrowing power", async() => {
            assert.equal(
                await treasury.power(),
                daiTokens.toString(),
                "Should return posted collateral * collateralization ratio"
            );
        });

        it("allows to withdraw collateral for user", async() => {
            assert.equal(
                await weth.balanceOf(user),
                0,
            );
            
            await treasury.pullWeth(user, wethTokens, { from: owner });

            // Test transfer of collateral
            assert.equal(
                (await weth.balanceOf(user)),
                wethTokens.toString(),
            );

            // Test collateral registering via `frob`
            assert.equal(
                (await vat.urns(WETH, treasury.address)).ink,
                0
            );
        });

        it("pulls dai borrowed from MakerDAO for user", async() => {
            // Test with two different stability rates, if possible.
            await treasury.pullDai(user, daiTokens, { from: owner });

            assert.equal(
                await dai.balanceOf(user),
                daiTokens.toString(),
            );
            assert.equal(
                (await vat.urns(WETH, treasury.address)).art,
                daiDebt.toString(),
            );
        });

        it("pulls chai converted from dai borrowed from MakerDAO for user", async() => {
            // Test with two different stability rates, if possible.
            await treasury.pullChai(user, chaiTokens, { from: owner });

            assert.equal(
                await chai.balanceOf(user),
                chaiTokens.toString(),
            );
            assert.equal(
                (await vat.urns(WETH, treasury.address)).art,
                daiDebt.toString(),
            );
        });

        it("shouldn't allow borrowing beyond power", async() => {
            await treasury.pullDai(user, daiTokens, { from: owner });
            assert.equal(
                await treasury.power(),
                daiTokens.toString(),
                "We should have " + daiTokens + " dai borrowing power.",
            );
            assert.equal(
                await treasury.debt(),
                daiTokens.toString(),
                "We should have " + daiTokens + " dai debt.",
            );
            await expectRevert(
                treasury.pullDai(user, 1, { from: owner }), // Not a wei more borrowing
                "Vat/sub",
            );
        });
    
        describe("with a dai debt towards MakerDAO", () => {
            beforeEach(async() => {
                await treasury.pullDai(user, daiTokens, { from: owner });
            });

            it("returns treasury debt", async() => {
                assert.equal(
                    (await treasury.debt()),
                    daiTokens.toString(),
                    "Should return borrowed dai"
                );
            });

            it("pushes dai that repays debt towards MakerDAO", async() => {
                // Test `normalizedAmount >= normalizedDebt`
                await dai.approve(treasury.address, daiTokens, { from: user });
                await treasury.pushDai(user, daiTokens, { from: owner });

                assert.equal(
                    await dai.balanceOf(user),
                    0
                );
                assert.equal(
                    (await vat.urns(WETH, treasury.address)).art,
                    0,
                );
                assert.equal(
                    await vat.dai(treasury.address),
                    0
                );
            });

            it("pushes chai that repays debt towards MakerDAO", async() => {
                await dai.approve(chai.address, daiTokens, { from: user });
                await chai.join(user, daiTokens, { from: user });
                await chai.approve(treasury.address, chaiTokens, { from: user }); 
                await treasury.pushChai(user, chaiTokens, { from: owner });

                assert.equal(
                    await dai.balanceOf(user),
                    0
                );
                assert.equal(
                    (await vat.urns(WETH, treasury.address)).art,
                    0,
                );
                assert.equal(
                    await vat.dai(treasury.address),
                    0
                );
            });
        });
    });
});
