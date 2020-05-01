const Vat= artifacts.require('./Vat');
const GemJoin = artifacts.require('./GemJoin');
const MockTreasury = artifacts.require('./MockTreasury');
const MockContract = artifacts.require("./MockContract")
const truffleAssert = require('truffle-assertions');
const helper = require('ganache-time-traveler');
const ERC20 = artifacts.require("./TestERC20");
var ethers = require('ethers');

contract('Treasury', async (accounts) =>  {
    let vat;
    let gold;
    let ilk = web3.utils.fromAscii("gold")
    let Line = web3.utils.fromAscii("Line")
    let spot = web3.utils.fromAscii("spot")
    let linel = web3.utils.fromAscii("line")
    let owner = accounts[0];
    let account1 = accounts[1];
    const ray  = "1000000000000000000000000000";
    const supply = web3.utils.toWei("1000");
    const power = web3.utils.toBN('49')
    const limits =  web3.utils.toBN('10').pow(power).toString();
    console.log(limits);


    beforeEach('setup', async() => {
        vat = await Vat.new();

        gold = await ERC20.new(supply); 
        await vat.init(ilk);
        gemA = await GemJoin.new(vat.address, ilk, gold.address);

        await vat.file(ilk, spot,    ray);
        await vat.file(ilk, linel, limits);
        await vat.file(Line,       limits);

        await gold.approve(gemA.address, supply);
        await gold.approve(vat.address, supply); 

        await vat.rely(vat.address);
        await vat.rely(gemA.address);

        await gemA.join(owner, supply);

    });

    describe("initial tests of vat", () => {

        it("should setup vat", async() => {
            let spot = (await vat.ilks(ilk)).spot.toString()
            assert(spot == ray, "spot not initialized")

        });

        it("should join funds", async() => {
            let testA = web3.utils.toWei("500");
            await gold.mint(testA , {from: account1});
            await gold.approve(gemA.address, testA, {from: account1}); 
            await gemA.join(account1, testA, {from: account1});
            assert.equal(
                (await gold.balanceOf(gemA.address)),   
                web3.utils.toWei("1500")
            );

        });


        it("should deposit and withdraw collateral", async() => {
            let amount = web3.utils.toWei("6");
            await vat.frob(ilk, owner, owner, owner, amount, 0);
            let ink = (await vat.urns(ilk, owner)).ink.toString()
            assert.equal(
                ink,   
                amount
            );
            let unfrob = web3.utils.toWei("-6");
            await vat.frob(ilk, owner, owner, owner, unfrob, 0);
            let ink2 = (await vat.urns(ilk, owner)).ink.toString()
            assert.equal(
                ink2,   
                "0"
            );
        });

        it("should borrow and return Dai", async() => {
            let collateral = web3.utils.toWei("6");
            let dai = web3.utils.toWei("1");
            await vat.frob(ilk, owner, owner, owner, collateral, dai);
            //let ink = (await vat.urns(ilk, owner)).ink.toString();
            let balance = (await vat.dai(owner)).toString();
            const power = web3.utils.toBN('45')
            const daiRad =  web3.utils.toBN('10').pow(power).toString(); //dai in rad
            assert.equal(
                balance,   
                daiRad
            );
            // Now remove debt and collateral
            let unfrob = web3.utils.toWei("-6");
            let undai = web3.utils.toWei("-1");
            await vat.frob(ilk, owner, owner, owner, unfrob, undai);
            //let ink2 = (await vat.dai(ilk, owner)).ink.toString()
            let balance2 = (await vat.dai(owner)).toString();
            assert.equal(
                balance2,   
                "0"
            );
        });


    });


});