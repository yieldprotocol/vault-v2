const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');
const Chai = artifacts.require('./Chai');
const ChaiOracle = artifacts.require('./ChaiOracle');
const Treasury = artifacts.require('Treasury');

const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const { expectRevert } = require('@openzeppelin/test-helpers');
const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Treasury - Lending', async (accounts) =>  {
    let [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let chai;
    let chaiOracle;
    let treasury;

    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")

    const limits =  toRad(10000);
    const spot = toRay(1.5);
    const rate = toRay(1.25);
    const chi = toRay(1.2);
    
    const daiDebt = toWad(120);
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chaiTokens = divRay(daiTokens, chi);

    beforeEach(async() => {
        // Set up vat, join and weth
        vat = await Vat.new();
        await vat.init(ilk, { from: owner }); // Set ilk rate to 1.0

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); 
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Setup pot
        pot = await Pot.new(vat.address);

        // Setup chai
        chai = await Chai.new(
            vat.address,
            pot.address,
            daiJoin.address,
            dai.address,
        );

        // Setup chaiOracle
        chaiOracle = await ChaiOracle.new(pot.address, { from: owner });

        // Permissions
        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.rely(pot.address, { from: owner });
        await vat.hope(daiJoin.address, { from: owner });

        // Set chi
        await pot.setChi(chi, { from: owner });
        
        treasury = await Treasury.new(
            dai.address,
            chai.address,
            chaiOracle.address,
            weth.address,
            daiJoin.address,
            wethJoin.address,
            vat.address,
        );
        await treasury.orchestrate(owner, { from: owner });
        // await treasury.orchestrate(user, { from: owner });
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
        
        await weth.deposit({ from: owner, value: wethTokens});
        await treasury.pushWeth(treasury.address, wethTokens, { from: owner });

        // Test transfer of collateral
        assert.equal(
            await weth.balanceOf(wethJoin.address),
            wethTokens.toString(),
        );

        // Test collateral registering via `frob`
        assert.equal(
            (await vat.urns(ilk, treasury.address)).ink,
            wethTokens.toString(),
        );
    });

    describe("with posted collateral", () => {
        beforeEach(async() => {
            await weth.deposit({ from: owner, value: wethTokens});
            await treasury.pushWeth(treasury.address, wethTokens, { from: owner });
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
                (await vat.urns(ilk, treasury.address)).ink,
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
                (await vat.urns(ilk, treasury.address)).art,
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
                (await vat.urns(ilk, treasury.address)).art,
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
                    (await vat.urns(ilk, treasury.address)).art,
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
                    (await vat.urns(ilk, treasury.address)).art,
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