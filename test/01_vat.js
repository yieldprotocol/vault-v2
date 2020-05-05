const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require("TestERC20");


contract('vat', async (accounts) =>  {
    let vat;
    let gold;
    let goldJoin;
    let dai;
    let daiJoin;
    let ilk = web3.utils.fromAscii("gold")
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

        gold = await ERC20.new(supply, { from: owner }); 
        goldJoin = await GemJoin.new(vat.address, ilk, gold.address, { from: owner });

        dai = await ERC20.new(0, { from: owner }); 
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spot,    ray, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line,       limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address, { from: owner });      // `owner` authorizing `vat` to operate for `vat`?
        await vat.rely(goldJoin.address, { from: owner }); // `owner` authorizing `goldJoin` to operate for `vat`
        await vat.rely(daiJoin.address, { from: owner });  // `owner` authorizing `daiJoin` to operate for `vat`
    });

    it("should setup vat", async() => {
        let spot = (await vat.ilks(ilk)).spot.toString()
        assert(spot == ray, "spot not initialized")
    });

    it("should join funds", async() => {
        assert.equal(
            (await gold.balanceOf(goldJoin.address)),   
            web3.utils.toWei("0")
        );
        let amount = web3.utils.toWei("500");
        await gold.mint(account1, amount, { from: account1 });
        await gold.approve(goldJoin.address, amount, { from: account1 }); 
        await goldJoin.join(account1, amount, { from: account1 });
        assert.equal(
            (await gold.balanceOf(goldJoin.address)),   
            web3.utils.toWei("500")
        );
    });

    describe("with funds joined", () => {
        beforeEach(async() => {
            await gold.approve(goldJoin.address, supply, { from: owner });
            // await gold.approve(vat.address, supply); 

            await goldJoin.join(owner, supply, { from: owner });
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
                let ink = (await vat.urns(ilk, owner)).ink.toString();
                assert.equal(
                    ink,   
                    "0"
                );
            });

            it("should borrow Dai", async() => {
                let daiBorrowed = web3.utils.toWei("1");
                await vat.frob(ilk, owner, owner, owner, 0, daiBorrowed, { from: owner });
                let vatBalance = (await vat.dai(owner)).toString();
                const rad = web3.utils.toBN('45')
                const daiRad =  web3.utils.toBN('10').pow(rad).toString(); //dai in rad
                assert.equal(
                    vatBalance,   
                    daiRad
                );
                await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
                await daiJoin.exit(owner, daiBorrowed, { from: owner }); // Shouldn't we be able to exit vatBalance?
                let daiBalance = (await dai.balanceOf(owner)).toString();
                assert.equal(
                    daiBalance,   
                    daiBorrowed
                );
            });

            describe("with dai borrowed", () => {
                beforeEach(async() => {
                    let daiBorrowed = web3.utils.toWei("1");
                    await vat.frob(ilk, owner, owner, owner, 0, daiBorrowed, { from: owner });
                    await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
                    await daiJoin.exit(owner, daiBorrowed, { from: owner });
                });

                it("should return Dai", async() => {
                    let undai = web3.utils.toWei("-1");
                    let daiReturned = web3.utils.toWei("1");
                    await daiJoin.join(owner, daiReturned, { from: owner });
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
                    let daiReturned = web3.utils.toWei("1");
                    await daiJoin.join(owner, daiReturned, { from: owner });
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