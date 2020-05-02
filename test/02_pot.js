const Pot = artifacts.require('MockPot');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require("TestERC20");


contract('pot', async (accounts) =>  {
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
    const ray  = "1000000000000000000000000000";
    const supply = web3.utils.toWei("1000");
    const rad = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(rad).toString();
    // console.log(limits);


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        collateral = await ERC20.new(supply, { from: owner });
        collateralJoin = await GemJoin.new(vat.address, ilk, collateral.address, { from: owner });

        dai = await ERC20.new(0, { from: owner });
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        // Setup vat
        await vat.file(ilk, spot,    ray, { from: owner });
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
        let daiBorrowed = web3.utils.toWei("10");
        await vat.frob(ilk, owner, owner, owner, collateralPosted, daiBorrowed, { from: owner });
        await daiJoin.exit(owner, daiBorrowed, { from: owner });

        // Setup pot
        pot = await Pot.new(vat.address);
        await vat.rely(pot.address, { from: owner });
        // Do we need to set the dsr to something different than one?
    });

    it("should setup pot", async() => {
        let chi = await pot.chi.call();
        assert(chi == ray, "chi not initialized")

    });

    it("should join funds", async() => {
        assert.equal(
            (await dai.balanceOf(owner)),   
            web3.utils.toWei("10")
        );
        let daiSaved = web3.utils.toWei("1");
        // await pot.join(daiSaived, { from: owner });
        await pot.dripAndJoin(daiSaved, { from: owner });
        assert.equal(
            (await pot.pie(owner)).toString(),   
            web3.utils.toWei("1")
        );
    });
});