const Vat = artifacts.require('Vat');
const GemJoin = artifacts.require('GemJoin');
const DaiJoin = artifacts.require('DaiJoin');
const ERC20 = artifacts.require("TestERC20");


contract('Vat', async (accounts) =>  {
    const [ owner, user ] = accounts;
    let vat;
    let weth;
    let wethJoin;
    let dai;
    let daiJoin;

    let ilk = web3.utils.fromAscii("weth")
    let Line = web3.utils.fromAscii("Line")
    let spotName = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    const RAY  = "1000000000000000000000000000";
    const RAD = web3.utils.toBN('49')
    const supply = web3.utils.toWei("1000");
    const limits =  web3.utils.toBN('10').pow(RAD).toString();
    const spot  = "1500000000000000000000000000";
    const wethTokens = web3.utils.toWei("150");
    const daiTokens = web3.utils.toWei("100");
    // console.log(limits);


    beforeEach(async() => {
        vat = await Vat.new();
        await vat.init(ilk, { from: owner });

        weth = await ERC20.new(0, { from: owner }); 
        wethJoin = await GemJoin.new(vat.address, ilk, weth.address, { from: owner });

        dai = await ERC20.new(0, { from: owner }); 
        daiJoin = await DaiJoin.new(vat.address, dai.address, { from: owner });

        await vat.file(ilk, spotName, RAY, { from: owner });
        await vat.file(ilk, linel, limits, { from: owner });
        await vat.file(Line, limits); // TODO: Why can't we specify `, { from: owner }`?

        await vat.rely(vat.address, { from: owner });      // `owner` authorizing `vat` to operate for `vat`?
        await vat.rely(wethJoin.address, { from: owner }); // `owner` authorizing `wethJoin` to operate for `vat`
        await vat.rely(daiJoin.address, { from: owner });  // `owner` authorizing `daiJoin` to operate for `vat`
    });

    it("should setup vat", async() => {
        assert(
            (await vat.ilks(ilk)).spot,
            spot,
            "spot not initialized",
        )
    });

    it("should join funds", async() => {
        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            0,
        );

        await weth.mint(owner, wethTokens, { from: owner });
        await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
        await wethJoin.join(owner, wethTokens, { from: owner });

        assert.equal(
            await weth.balanceOf(wethJoin.address),   
            wethTokens,
        );
    });

    describe("with funds joined", () => {
        beforeEach(async() => {
            await weth.mint(owner, wethTokens, { from: owner });
            await weth.approve(wethJoin.address, wethTokens, { from: owner }); 
            await wethJoin.join(owner, wethTokens, { from: owner });
        });

        it("should deposit collateral", async() => {
            await vat.frob(ilk, owner, owner, owner, wethTokens, 0, { from: owner });
            
            assert.equal(
                (await vat.urns(ilk, owner)).ink,   
                wethTokens,
            );
        });

        it("should deposit collateral and borrow Dai", async() => {
            
            await vat.frob(ilk, owner, owner, owner, wethTokens, daiTokens, { from: owner });
            //let ink = (await vat.urns(ilk, owner)).ink.toString();
            let balance = (await vat.dai(owner)).toString();
            const pow = web3.utils.toBN('47')
            const daiRad =  web3.utils.toBN('10').pow(pow).toString(); // 100 dai in RAD
            assert.equal(
                balance,   
                daiRad
            );
            let ink = (await vat.urns(ilk, owner)).ink.toString()
            assert.equal(
                ink,   
                wethTokens
            );
        });

        describe("with collateral deposited", () => {
            beforeEach(async() => {
                await vat.frob(ilk, owner, owner, owner, wethTokens, 0, { from: owner });
            });
     
            it("should withdraw collateral", async() => {
                const unfrob = web3.utils.toWei("-150");
                await vat.frob(ilk, owner, owner, owner, unfrob, 0, { from: owner });

                assert.equal(
                    (await vat.urns(ilk, owner)).ink,   
                    "0"
                );
            });

            it("should borrow Dai", async() => {

                await vat.frob(ilk, owner, owner, owner, 0, daiTokens, { from: owner });
                let vatBalance = (await vat.dai(owner)).toString();
                const pow = web3.utils.toBN('47')
                const daiRad =  web3.utils.toBN('10').pow(pow).toString(); // 100 dai in RAD
                assert.equal(
                    vatBalance,   
                    daiRad
                );
                await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
                await daiJoin.exit(owner, daiTokens, { from: owner }); // Shouldn't we be able to exit vatBalance?

                assert.equal(
                    await dai.balanceOf(owner),   
                    daiTokens
                );
            });

            describe("with dai borrowed", () => {
                beforeEach(async() => {
                    await vat.frob(ilk, owner, owner, owner, 0, daiTokens, { from: owner });
                    await vat.hope(daiJoin.address, { from: owner }); // `owner` allowing daiJoin to move his dai.
                    await daiJoin.exit(owner, daiTokens, { from: owner });
                });

                it("should return Dai", async() => {
                    let undai = web3.utils.toWei("-100");

                    await daiJoin.join(owner, daiTokens, { from: owner });
                    await vat.frob(ilk, owner, owner, owner, 0, undai, { from: owner });

                    assert.equal(
                        await vat.dai(owner),   
                        "0"
                    );
                });

                it("should return Dai and withdraw collateral", async() => {
                    let unfrob = web3.utils.toWei("-150");
                    let undai = web3.utils.toWei("-100");

                    await daiJoin.join(owner, daiTokens, { from: owner });
                    await vat.frob(ilk, owner, owner, owner, unfrob, undai, { from: owner });
                    //let ink2 = (await vat.dai(ilk, owner)).ink.toString()
                    
                    assert.equal(
                        await vat.dai(owner),   
                        "0"
                    );
                    assert.equal(
                        (await vat.urns(ilk, owner)).ink,   
                        "0"
                    );
                });
            });
        });
    });
});