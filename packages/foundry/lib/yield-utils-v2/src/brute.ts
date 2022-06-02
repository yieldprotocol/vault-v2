import { ethers } from 'hardhat'
import { keccak256, toUtf8Bytes } from 'ethers/lib/utils'

 
(async () => {
    let i = 8340000000
    let foundROOT = 0
    let foundLOCK = 0
    while (foundROOT < 2 || foundLOCK < 2) {
        if (foundROOT < 2) {
            const ROOT = 'ROOT'+i+'()'
            const sigROOT = keccak256(toUtf8Bytes(ROOT)).slice(0, 10)
            if (sigROOT === '0x00000000') {
                console.log(`${sigROOT} ${ROOT}`)
                foundROOT++
            }
        }

        if (foundLOCK < 2) {
            const LOCK = 'LOCK'+i+'()'
            const sigLOCK = keccak256(toUtf8Bytes(LOCK)).slice(0, 10)
            if (sigLOCK === '0xffffffff') {
                console.log(`${sigLOCK} ${LOCK}`)
                foundLOCK++
            }
        }
        
        i++
        if (i % 10000000 == 0 ) console.log(i)
    }
})()

// 2250000000