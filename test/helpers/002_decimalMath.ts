const DecimalMath = artifacts.require('DecimalMathMock')

// @ts-ignore
import { expectRevert } from '@openzeppelin/test-helpers'
import { id } from 'ethers/lib/utils'
import { assert } from 'chai'

contract('DecimalMath', async (accounts: string[]) => {
  let [owner] = accounts

  let math: any

  const one = '1000000000000000000000000000'
  const two = '2000000000000000000000000000'
  const three = '3000000000000000000000000000'
  const six = '6000000000000000000000000000'

  beforeEach(async () => {
    math = await DecimalMath.new({ from: owner })
  })

  it('muld', async () => {
    assert.equal((await math.muld_(two, three)).toString(), six)
  })

  it('divd', async () => {
    assert.equal((await math.divd_(six, three)).toString(), two)
  })

  it('divdrup', async () => {
    assert.equal((await math.divdrup_(six, three)).toString(), two)
    assert.equal((await math.divdrup_(one, three)).toString(), '333333333333333333333333334')
    assert.equal((await math.divdrup_(1, two)).toString(), '1')
  })

  it('muldrup', async () => {
    assert.equal((await math.muldrup_(two, three)).toString(), six)
    assert.equal((await math.muldrup_('6666666666666666666666666666', '300000000000000000000000000')).toString(), two)
    assert.equal((await math.muldrup_('1000000000000000000000000001', '1')).toString(), '2')
  })
})
