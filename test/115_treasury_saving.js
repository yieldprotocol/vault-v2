const { setupMaker, newTreasury, getDai } = require("./shared/fixtures");
const {
    WETH,
    rate1,
    daiDebt1,
    daiTokens1,
    wethTokens1,
    chaiTokens1,
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
            chai
        } = await setupMaker());
        treasury = await newTreasury();

        // Setup tests - Allow owner to interact directly with Treasury, not for production
        await treasury.orchestrate(owner, { from: owner });

        // Borrow some dai
        await getDai(user, daiTokens1, rate1);
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
            daiTokens1.toString(),
            "User does not have dai",
        );
        
        await dai.approve(treasury.address, daiTokens1, { from: user }); 
        await treasury.pushDai(user, daiTokens1, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens1.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens1.toString(),
            "Treasury should have " + daiTokens1 + " savings in dai units, instead has " + await treasury.savings.call(),
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
            daiTokens1.toString(),
            "User does not have dai",
        );
        
        await dai.approve(chai.address, daiTokens1, { from: user });
        await chai.join(user, daiTokens1, { from: user });
        await chai.approve(treasury.address, chaiTokens1, { from: user }); 
        await treasury.pushChai(user, chaiTokens1, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await chai.balanceOf(treasury.address),
            chaiTokens1.toString(),
            "Treasury should have chai"
        );
        assert.equal(
            await treasury.savings.call(),
            daiTokens1.toString(),
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
            await dai.approve(treasury.address, daiTokens1, { from: user }); 
            await treasury.pushDai(user, daiTokens1, { from: owner });
        });

        it("pulls dai from savings", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens1.toString(),
                "Treasury does not have chai"
            );
            assert.equal(
                await treasury.savings.call(),
                daiTokens1.toString(),
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                0,
                "User has dai",
            );
            
            await treasury.pullDai(user, daiTokens1, { from: owner });

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
                daiTokens1.toString(),
                "User should have dai",
            );
        });


        it("pulls chai from savings", async() => {
            assert.equal(
                await chai.balanceOf(treasury.address),
                chaiTokens1.toString(),
                "Treasury does not have chai"
            );
            assert.equal(
                await treasury.savings.call(),
                daiTokens1.toString(),
                "Treasury does not report savings in dai units"
            );
            assert.equal(
                await dai.balanceOf(user),
                0,
                "User has dai",
            );
            
            await treasury.pullChai(user, chaiTokens1, { from: owner });

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
                chaiTokens1.toString(),
                "User should have chai",
            );
        });
    });
});
