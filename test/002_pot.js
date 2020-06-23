const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const Weth = artifacts.require("WETH9");
const ERC20 = artifacts.require("TestERC20");
const Pot = artifacts.require('Pot');

const { toWad, toRay, toRad, addBN, subBN, mulRay, divRay } = require('./shared/utils');

contract('Pot', async (accounts) =>  {
    const [ owner, user ] = accounts;

    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;
    let pot;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const limits =  toRad(10000);
    const spot  = toRay(1.5);
    const rate  = toRay(1.25);
    const daiDebt = toWad(96);    // Dai debt for `frob`: 100
    const daiTokens = mulRay(daiDebt, rate);
    const wethTokens = divRay(daiTokens, spot);
    const chi = toRay(1.2)
    const daiInPot = divRay(daiTokens, chi);


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await Weth.new({ from: owner });
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, spot, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); 

        await vat.rely(vat.address, { from: owner });
        await vat.rely(wethJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });
        await vat.fold(ilk, vat.address, subBN(rate, toRay(1)), { from: owner }); // Fold only the increase from 1.0

        // Vat permissions
        await vat.hope(daiJoin.address, { from: owner });

        // Borrow some dai
        await weth.deposit({ from: owner, value: wethTokens});
        await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
        await wethJoin.join(owner, wethTokens, { from: owner });
        await vat.frob(ilk, owner, owner, owner, wethTokens, daiDebt, { from: owner });
        await daiJoin.exit(owner, daiTokens, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
    });

    it("should setup pot", async() => {
        assert.equal(
            await pot.chi.call(),
            toRay(1).toString(),
            "chi not initialized",
        );

    });

    it("should set chi to a target", async() => {
        await pot.setChi(chi, { from: owner });
        assert.equal(
            await pot.chi.call(),
            chi.toString(),
            "chi not set to 1.25",
        );
        assert.equal(
            await pot.drip.call({ from: owner }),
            chi.toString(),
            "chi not set to 1.25",
        );
    });

    it("should save dai in the pot", async() => {
        assert.equal(
            await dai.balanceOf(owner),   
            daiTokens.toString(),
            "Owner does not have dai"
        );
        assert.equal(
            await pot.chi.call(),
            toRay(1).toString(),
            "chi not initialized",
        );
        
        await daiJoin.join(owner, daiTokens, { from: owner }); // The dai needs to be joined to the vat first.
        await vat.hope(pot.address, { from: owner });         // The user joining dai to the Pot needs to have authorized pot.address in the vat first
        await pot.mockJoin(daiInPot, { from: owner });            // The transaction where the user joins Dai to the Pot needs to have called drip() as well
        // await pot.dripAndJoin(daiSaved, { from: owner });

        assert.equal(
            await pot.pie(owner),   
            daiInPot.toString(),
            "The Dai is not in the Pot"
        );
    });

    it("should save dai in the pot proportionally to chi", async() => {
        assert.equal(
            await dai.balanceOf(owner),   
            daiTokens.toString(),
            "Owner does not have dai"
        );
        assert.equal(
            await pot.pie(owner),   
            0,
            "Owner has dai in the pot",
        );

        await pot.setChi(chi, { from: owner });

        await daiJoin.join(owner, daiTokens, { from: owner });
        await vat.hope(pot.address, { from: owner });
        await pot.mockJoin(daiInPot, { from: owner }); // The Pot will store normalized dai = joined dai / chi
        // await pot.dripAndJoin(daiSaved, { from: owner });
        assert.equal(
            await dai.balanceOf(owner),   
            0,
            "Owner should not have dai"
        );
        assert.equal(
            await pot.pie(owner),   
            daiInPot.toString(),
            "Dai should be in the pot",
        );
    });

    describe("with dai saved in the Pot", () => {
        beforeEach(async() => {
            await pot.setChi(chi, { from: owner });
            await daiJoin.join(owner, daiTokens, { from: owner });
            await vat.hope(pot.address, { from: owner });
            await pot.mockJoin(daiInPot, { from: owner });
        });

        it("should get dai out of the pot", async() => {
            assert.equal(
                await dai.balanceOf(owner),   
                0,
                "Owner has dai in hand",
            );
            assert.equal(
                await vat.dai.call(owner),   
                0,
                "Owner has dai in the vat",
            );
            assert.equal(
                await pot.pie(owner),   
                daiInPot.toString(),
                "Owner does not have dai in the Pot",
            );
            
            await pot.exit(daiInPot, { from: owner });            // The transaction where the user gets Dai out of the Pot needs to have called drip() as well
            await daiJoin.exit(owner, daiTokens, { from: owner }); // The dai needs to be joined to the vat first.
            assert.equal(
                await pot.pie(owner),   
                0,
                "Owner should have no dai in the Pot",
            );
            assert.equal(
                await dai.balanceOf(owner),   
                daiTokens.toString(),
                "Owner should have received the joined dai",
            );
        });
    });
});