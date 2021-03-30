import { YieldEnvironment } from '../test/shared/fixtures'
import { ethers, waffle } from 'hardhat'


/**
 * 
 * README: 
 * npx hardhat run ./scripts/devEnv.ts --network localhost
 *
 */

const { loadFixture } = waffle

const base:Uint8Array = ethers.utils.randomBytes(6);
const ilks:Uint8Array[] = Array.from({length: 3}, () => ethers.utils.randomBytes(6));

const series:Uint8Array[] = Array.from({length: 5}, () => ethers.utils.randomBytes(6));
const ilkNames: string[] = ['DAI', 'USDC', 'USDT']

const externalTestAccounts = [
    "0x885Bc35dC9B10EA39f2d7B3C94a7452a9ea442A7",
]

async function fixture() {
    const [ ownerAcc ] = await ethers.getSigners();
    return await YieldEnvironment.setup(
        ownerAcc,
        ilkNames.map((name:string)=> ethers.utils.formatBytes32String(name).slice(0, 14) ),
        // ...ilks.map((x:Uint8Array) => ethers.utils.hexlify(x)),
        series.map((x:Uint8Array) => ethers.utils.hexlify(x))
        )
}

const fundExternalAccounts = async  () => {
    const [ ownerAcc ] = await ethers.getSigners();
    await Promise.all(
        externalTestAccounts.map((to:string)=> {
            ownerAcc.sendTransaction({to,value: ethers.utils.parseEther("100")})
        })
    )
    console.log('External Accounts funded with 100ETH.')
};

loadFixture(fixture).then( ( env:YieldEnvironment)  => { 

    console.log(`"Cauldron": "${env.cauldron.address}",`)
    console.log(`"Ladle" : "${env.ladle.address}",`)
    console.log(`"Witch" : "${env.witch.address}"`)
    
    console.log('Assets:')
    env.assets.forEach((value:any, key:any)=>{ console.log(`"${key}" : "${value.address}",` ) })

    console.log('Oracles:')
    env.oracles.forEach((value:any, key:any)=>{ console.log(`"${key}" : "${value.address}",` ) })
    
    console.log('Series:')
    env.series.forEach((value:any, key:any)=>{ console.log(`"${key}" : "${value.address}",` ) })
    
    console.log('Joins:')
    env.joins.forEach((value:any, key:any)=>{ console.log(`"${key}" : "${value.address}",` ) })

    console.log('Vaults:')
    env.vaults.forEach((value:any, key:any) => console.log(value))

    fundExternalAccounts();

}

);