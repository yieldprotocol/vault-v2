const Pot = artifacts.require('Pot');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require("TestERC20");

const { BN } = require('@openzeppelin/test-helpers');

contract('Pot', async (accounts) =>  {
    let vat;
    let collateral;
    let collateralJoin;
    let dai;
    let daiJoin;
    let pot;
    let ilk = web3.utils.fromAscii("ETH-A")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    let owner = accounts[0];
    let account1 = accounts[1];
    const RAY  = "1000000000000000000000000000";
    const supply = web3.utils.toWei("1000");
    const RAD = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    // console.log(limits);


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        collateral = await ERC20.new(supply, { from: owner });
        collateralJoin = await GemJoin.new(vat.address, ilk, collateral.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address, { from: owner });
        await vat.rely(collateralJoin.address, { from: owner });
        await vat.rely(daiJoin.address, { from: owner });

        await vat.hope(daiJoin.address, { from: owner });

        // Borrow some dai
        await collateral.approve(collateralJoin.address, supply, { from: owner });
        await collateralJoin.join(owner, supply, { from: owner });
        let collateralPosted = web3.utils.toWei("60");
        let daiBorrowed = web3.utils.toWei("11");
        await vat.frob(ilk, owner, owner, owner, collateralPosted, daiBorrowed, { from: owner });
        await daiJoin.exit(owner, daiBorrowed, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Do we need to set the dsr to something different than one?
    });

    it("should setup pot", async() => {
        const chi = await pot.chi.call();
        assert(chi == RAY, "chi not initialized");

    });

    it("should set chi to a target", async() => {
        const chi  = "1100000000000000000000000000";
        await pot.setChi(chi, { from: owner });
        assert.equal(
            await pot.chi.call(),
            chi,
            "chi not set to 1.1",
        );
        assert.equal(
            await pot.drip.call({ from: owner }),
            chi,
            "chi not set to 1.1",
        );
    });

    it("should save dai in the pot", async() => {
        assert.equal(
            (await dai.balanceOf(owner)),   
            web3.utils.toWei("11"),
            "Preconditions not met - dai.balanceOf(owner)"
        );
        let chi = await pot.chi.call();
        assert(chi == RAY, "Preconditions not met - chi not 1.0");
        let daiOwner = (await vat.dai(owner)).toString();
        assert(daiOwner, web3.utils.toWei("11"), "Preconditions not met - vat.dai(owner)");
        
        let daiSaved = web3.utils.toWei("1");
        await daiJoin.join(owner, daiSaved, { from: owner }); // The dai needs to be joined to the vat first.
        await vat.hope(pot.address, { from: owner });         // The user joining dai to the Pot needs to have authorized pot.address in the vat first
        await pot.mockJoin(daiSaved, { from: owner });            // The transaction where the user joins Dai to the Pot needs to have called drip() as well
        // await pot.dripAndJoin(daiSaved, { from: owner });
        assert.equal(
            (await pot.pie(owner)).toString(),   
            web3.utils.toWei("1")
        );
    });

    it("should save dai in the pot proportionally to chi", async() => {
        assert.equal(
            (await dai.balanceOf(owner)),   
            web3.utils.toWei("11"),
            "Preconditions not met - dai.balanceOf(owner)"
        );
        let daiOwner = (await vat.dai(owner)).toString();
        assert(daiOwner, web3.utils.toWei("10"), "Preconditions not met - vat.dai(owner)");
        
        const chi  = "1100000000000000000000000000";
        await pot.setChi(chi, { from: owner });

        let daiJoined = web3.utils.toWei("11");
        let daiNormalized = web3.utils.toWei("10");
        const daiInVat =  "11000000000000000000000000000000000000000000000"; // Vat stores dai in RAD units. Tsk tsk.
        await daiJoin.join(owner, daiJoined, { from: owner });
        assert.equal(
            (await vat.dai.call(owner)).toString(),   
            daiInVat,
            "Owner should have the joined dai in the vat",
        );
        await vat.hope(pot.address, { from: owner });
        await pot.mockJoin(daiNormalized, { from: owner }); // The Pot will store normalized dai = joined dai / chi
        // await pot.dripAndJoin(daiSaved, { from: owner });
        assert.equal(
            (await vat.dai.call(owner)),
            0,
            "Owner should have no dai in the vat",
        );
        assert.equal(
            (await pot.pie(owner)).toString(),   
            daiNormalized,
            "Normalized dai was not in the pot",
        );
    });

    describe("with dai saved in the Pot and chi = 1.1", () => {
        beforeEach(async() => {
            const chi  = "1100000000000000000000000000";
            await pot.setChi(chi, { from: owner });
            let daiJoined = web3.utils.toWei("11");
            let daiNormalized = web3.utils.toWei("10");
            await daiJoin.join(owner, daiJoined, { from: owner });
            await vat.hope(pot.address, { from: owner });
            await pot.mockJoin(daiNormalized, { from: owner });
        });

        it("should get dai out of the pot", async() => {
            let daiJoined = web3.utils.toWei("11");
            let daiNormalized = web3.utils.toWei("10");
            assert.equal(
                (await dai.balanceOf(owner)),   
                0,
                "Owner has dai in hand",
            );
            assert.equal(
                (await vat.dai.call(owner)),   
                0,
                "Owner has dai in the vat",
            );
            assert.equal(
                (await pot.pie(owner)).toString(),   
                daiNormalized,
                "Owner does not have 10 normalized dai in the Pot",
            );
            
            await pot.exit(daiNormalized, { from: owner });            // The transaction where the user gets Dai out of the Pot needs to have called drip() as well
            await daiJoin.exit(owner, daiJoined, { from: owner }); // The dai needs to be joined to the vat first.
            assert.equal(
                (await pot.pie(owner)).toString(),   
                0,
                "Owner should have no dai in the Pot",
            );
            assert.equal(
                (await vat.dai.call(owner)),   
                0,
                "Owner should have no dai in the vat",
            );
            assert.equal(
                (await dai.balanceOf(owner)),   
                daiJoined,
                "Owner should have received the joined dai",
            );
        });
    });
});