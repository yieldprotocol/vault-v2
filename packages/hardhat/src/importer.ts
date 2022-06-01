import { readdirSync, writeFileSync } from 'fs'
import path from 'path'

const exclude: string[] = ['test', 'convex/interfaces', 'lido/WstETHMock.sol']

const importPaths: string[] = []
const base: string = '@yield-protocol/vault-v2/contracts/'

const solFilesInDirectory = (directoryPath: string, pathAddition = '') => {
  const files = readdirSync(directoryPath)

  files.forEach(function (file) {
    if (!exclude.includes(file) && !exclude.some(path => `${directoryPath}/${file}`.includes(path))) {
      if (file.includes('.sol')) {
        const fileWithoutExtension = file.substring(0, file.length - 4)
        importPaths.push(`import {${fileWithoutExtension}} from "${base}${pathAddition}${file}";\n`)
      } else if (!file.includes('.') && !exclude.includes(file)) {
        const newDirectoryPath = `${directoryPath}/${file}`
        solFilesInDirectory(newDirectoryPath, `${pathAddition}${file}/`)
      }
    }
  });
  return importPaths
}

async function main() {
  const entryDirectoryPath = path.join(__dirname, '../../foundry/contracts');
  const imports = solFilesInDirectory(entryDirectoryPath)

  let str = `// SPDX-License-Identifier: BUSL-1.1 \npragma solidity 0.8.14;\n\n`;

  imports.forEach(imp => {
    str += imp
  })

  const importerFilePath = path.join(__dirname, '../contracts/Importer.sol')

  writeFileSync(importerFilePath, str)
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
