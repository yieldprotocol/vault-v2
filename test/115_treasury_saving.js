const { setupYield } = require("./shared/fixtures");
const {
    WETH,
    daiDebt,
    daiTokens,
    wethTokens,
    chaiTokens,
} = require ("./shared/utils");

contract('Treasury - Saving', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
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
        } = await setupYield(owner, user))

        // Borrow some dai
        await weth.deposit({ from: user, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: user }); 
        await wethJoin.join(user, wethTokens, { from: user });
        await vat.frob(WETH, user, user, user, wethTokens, daiDebt, { from: user });
        await daiJoin.exit(user, daiTokens, { from: user });
    });

    it("allows to save dai", async() => {
        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury has chai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has savings in dai units"
        );
        assert.equal(
            await dai.balanceOf(user),
            daiTokens.toString(),
            "User does not have dai",
        );
        
        await dai.approve(treasury.address, daiTokens, { from: user }); 
        await treasury.pushDai(user, daiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens.toString(),
            "Treasury should have " + daiTokens + " savings in dai units, instead has " + await treasury.savings.call(),
        );
        assert.equal(
            await dai.balanceOf(user),
            0,
            "User should not have dai",
        );
    });

    it("allows to save chai", async() => {
        assert.equal(
            await chai.balanceOf(treasury.address),
            0,
            "Treasury has chai",
        );
        assert.equal(
            await treasury.savings.call(),
            0,
            "Treasury has savings in dai units"
        );
        assert.equal(
            await dai.balanceOf(user),
            daiTokens.toString(),
            "User does not have dai",
        );
        
        await dai.approve(chai.address, daiTokens, { from: user });
        await chai.join(user, daiTokens, { from: user });
        await chai.approve(treasury.address, chaiTokens, { from: user }); 
        await treasury.pushChai(user, chaiTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens.toString(),
            "Treasury should report savings in dai units"
        );
        assert.equal(
            await chai.balanceOf(user),
            0,
            "User should not have chai",
        );
    });

    describe("with savings", () => {
        beforeEach(async() => {
            await dai.approve(treasury.address, daiTokens, { from: user }); 
            await treasury.pushDai(user, daiTokens, { from: owner });
        });

        it("pulls dai from savings", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai"
            );
            assert.equal(
                await treasury.savings.call(),
                daiTokens.toString(),
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                0,
                "User has dai",
            );
            
            await treasury.pullDai(user, daiTokens, { from: owner });

            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await treasury.savings.call(),
                0,
                "Treasury should not have savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                daiTokens.toString(),
                "User should have dai",
            );
        });


        it("pulls chai from savings", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens.toString(),
                "Treasury does not have chai"
            );
            assert.equal(
                await treasury.savings.call(),
                daiTokens.toString(),
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                0,
                "User has dai",
            );
            
            await treasury.pullChai(user, chaiTokens, { from: owner });

            assert.equal(
                await chai.balanceOf(treasury.address),
                0,
                "Treasury should not have chai",
            );
            assert.equal(
                await treasury.savings.call(),
                0,
                "Treasury should not have savings in dai units"
            );
            assert.equal(
                await chai.balanceOf(user),
                chaiTokens.toString(),
                "User should have chai",
            );
        });
    });
});
