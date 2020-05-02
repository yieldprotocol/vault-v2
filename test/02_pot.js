const Pot = artifacts.require('Pot');
const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const ERC20 = artifacts.require("TestERC20");


contract('vat', async (accounts) =>  {
    let vat;
    let collateral;
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

        collateral = await ERC20.new(supply, { from: owner }); 
        await vat.init(ilk, { from: owner });
        collateralJoin = await GemJoin.new(vat.address, ilk, collateral.address, { from: owner });

        await vat.file(ilk, spot,    ray, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address, { from: owner });
        await vat.rely(collateralJoin.address, { from: owner });

        pot = await Pot.new(vat.address);
    });

    it("should setup pot", async() => {
        let chi = await pot.chi.call();
        assert(chi == ray, "chi not initialized")

    });

    it("should join funds", async() => {
        assert.equal(
            (await collateral.balanceOf(collateralJoin.address)),   
            web3.utils.toWei("0")
        );
        let amount = web3.utils.toWei("500");
        await collateral.mint(amount, { from: account1 });
        await collateral.approve(collateralJoin.address, amount, { from: account1 }); 
        await collateralJoin.join(account1, amount, { from: account1 });
        assert.equal(
            (await collateral.balanceOf(collateralJoin.address)),   
            web3.utils.toWei("500")
        );
    });

    describe("with funds joined", () => {
        beforeEach(async() => {
            await collateral.approve(collateralJoin.address, supply, { from: owner });
            // await collateral.approve(vat.address, supply); 

            await collateralJoin.join(owner, supply, { from: owner });
        });

        it("should deposit collateral", async() => {
            let collateral = web3.utils.toWei("6");
            await vat.frob(ilk, owner, owner, owner, collateral, 0, { from: owner });
            let ink = (await vat.urns(ilk, owner)).ink.toString()
            assert.equal(
                ink,   
                collateral
            );
        });

        it("should deposit collateral and borrow Dai", async() => {
            let collateral = web3.utils.toWei("6");
            let dai = web3.utils.toWei("1");
            await vat.frob(ilk, owner, owner, owner, collateral, dai, { from: owner });
            //let ink = (await vat.urns(ilk, owner)).ink.toString();
            let balance = (await vat.dai(owner)).toString();
            const rad = web3.utils.toBN('45')
            const daiRad =  web3.utils.toBN('10').pow(rad).toString(); //dai in rad
            assert.equal(
                balance,   
                daiRad
            );
            let ink = (await vat.urns(ilk, owner)).ink.toString()
            assert.equal(
                ink,   
                collateral
            );
        });

        describe("with collateral deposited", () => {
            beforeEach(async() => {
                let collateral = web3.utils.toWei("6");
                await vat.frob(ilk, owner, owner, owner, collateral, 0, { from: owner });
            });
     
            it("should withdraw collateral", async() => {
                let unfrob = web3.utils.toWei("-6");
                await vat.frob(ilk, owner, owner, owner, unfrob, 0, { from: owner });
                let ink = (await vat.urns(ilk, owner)).ink.toString()
                assert.equal(
                    ink,   
                    "0"
                );
            });

            it("should borrow Dai", async() => {
                let dai = web3.utils.toWei("1");
                await vat.frob(ilk, owner, owner, owner, 0, dai, { from: owner });
                let balance = (await vat.dai(owner)).toString();
                const rad = web3.utils.toBN('45')
                const daiRad =  web3.utils.toBN('10').pow(rad).toString(); //dai in rad
                assert.equal(
                    balance,   
                    daiRad
                );
            });

            describe("with dai borrowed", () => {
                beforeEach(async() => {
                    let dai = web3.utils.toWei("1");
                    await vat.frob(ilk, owner, owner, owner, 0, dai, { from: owner });
                });

                it("should return Dai", async() => {
                    let undai = web3.utils.toWei("-1");
                    await vat.frob(ilk, owner, owner, owner, 0, undai, { from: owner });
                    let balance = (await vat.dai(owner)).toString();
                    assert.equal(
                        balance,   
                        "0"
                    );
                });

                it("should return Dai and withdraw collateral", async() => {
                    let unfrob = web3.utils.toWei("-6");
                    let undai = web3.utils.toWei("-1");
                    await vat.frob(ilk, owner, owner, owner, unfrob, undai, { from: owner });
                    //let ink2 = (await vat.dai(ilk, owner)).ink.toString()
                    let balance = (await vat.dai(owner)).toString();
                    assert.equal(
                        balance,   
                        "0"
                    );
                    let ink = (await vat.urns(ilk, owner)).ink.toString()
                    assert.equal(
                        ink,   
                        "0"
                    );
                });
            });
        });
    });
});