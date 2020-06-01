const Pot = artifacts.require('Pot');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require("TestERC20");

const { toWad, toRay, toRad } = require('./shared/utils')

contract('Pot', async (accounts) =>  {
    const [ owner, user ] = accounts;

    let vat;
    let collateral;
    let collateralJoin;
    let dai;
    let daiJoin;
    let pot;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const spot  = 1;
    const chi = 1.2;
    const daiTokens = 120;
    const wethTokens = daiTokens * spot;
    const daiInPot = daiTokens / chi;
    const limits =  10000;
    // console.log(limits);


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        collateral = await ERC20.new(toWad(wethTokens), { from: owner });
        collateralJoin = await GemJoin.new(vat.address, ilk, collateral.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spotName, toRay(spot), { from: owner });
        await vat.file(ilk, linel, toRad(limits), { from: owner });
        await vat.file(Line, toRad(limits)); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address, { from: owner });
        await vat.rely(collateralJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        await vat.hope(daiJoin.address, { from: owner });

        // Borrow some dai
        await collateral.approve(collateralJoin.address, toWad(wethTokens), { from: owner });
        await collateralJoin.join(owner, toWad(wethTokens), { from: owner });
        await vat.frob(ilk, owner, owner, owner, toWad(wethTokens), toWad(daiTokens), { from: owner });
        await daiJoin.exit(owner, toWad(daiTokens), { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Do we need to set the dsr to something different than one?
    });

    it("should setup pot", async() => {
        assert.equal(
            await pot.chi.call(),
            toRay(1).toString(),
            "chi not initialized",
        );

    });

    it("should set chi to a target", async() => {
        const chi  = 1.2;
        await pot.setChi(toRay(chi), { from: owner });
        assert.equal(
            await pot.chi.call(),
            toRay(chi).toString(),
            "chi not set to 1.2",
        );
        assert.equal(
            await pot.drip.call({ from: owner }),
            toRay(chi).toString(),
            "chi not set to 1.2",
        );
    });

    it("should save dai in the pot", async() => {
        assert.equal(
            await dai.balanceOf(owner),   
            toWad(daiTokens).toString(),
            "Owner does not have dai"
        );
        assert.equal(
            await pot.chi.call(),
            toRay(1).toString(),
            "chi not initialized",
        );
        
        await daiJoin.join(owner, toWad(daiTokens), { from: owner }); // The dai needs to be joined to the vat first.
        await vat.hope(pot.address, { from: owner });         // The user joining dai to the Pot needs to have authorized pot.address in the vat first
        await pot.mockJoin(toWad(daiInPot), { from: owner });            // The transaction where the user joins Dai to the Pot needs to have called drip() as well
        // await pot.dripAndJoin(daiSaved, { from: owner });

        assert.equal(
            await pot.pie(owner),   
            toWad(daiInPot).toString(),
            "The Dai is not in the Pot"
        );
    });

    it("should save dai in the pot proportionally to chi", async() => {
        assert.equal(
            await dai.balanceOf(owner),   
            toWad(daiTokens).toString(),
            "Owner does not have dai"
        );
        assert.equal(
            await pot.pie(owner),   
            0,
            "Owner has dai in the pot",
        );

        await pot.setChi(toRay(chi), { from: owner });

        await daiJoin.join(owner, toWad(daiTokens), { from: owner });
        await vat.hope(pot.address, { from: owner });
        await pot.mockJoin(toWad(daiInPot), { from: owner }); // The Pot will store normalized dai = joined dai / chi
        // await pot.dripAndJoin(daiSaved, { from: owner });
        assert.equal(
            await dai.balanceOf(owner),   
            0,
            "Owner should not have dai"
        );
        assert.equal(
            await pot.pie(owner),   
            toWad(daiInPot).toString(),
            "Dai should be in the pot",
        );
    });

    describe("with dai saved in the Pot", () => {
        beforeEach(async() => {
            await pot.setChi(toRay(chi), { from: owner });
            await daiJoin.join(owner, toWad(daiTokens), { from: owner });
            await vat.hope(pot.address, { from: owner });
            await pot.mockJoin(toWad(daiInPot), { from: owner });
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
                toWad(daiInPot).toString(),
                "Owner does not have dai in the Pot",
            );
            
            await pot.exit(toWad(daiInPot), { from: owner });            // The transaction where the user gets Dai out of the Pot needs to have called drip() as well
            await daiJoin.exit(owner, toWad(daiTokens), { from: owner }); // The dai needs to be joined to the vat first.
            assert.equal(
                await pot.pie(owner),   
                0,
                "Owner should have no dai in the Pot",
            );
            assert.equal(
                await dai.balanceOf(owner),   
                toWad(daiTokens).toString(),
                "Owner should have received the joined dai",
            );
        });
    });
});