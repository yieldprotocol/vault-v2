Flatten the contracts and remove SPDX tags
```
for file in Cauldron FYToken Join Ladle Witch; do
npx hardhat flatten ../$file.sol | sed s/^.*SPDX.*$//g > $file.sol;
done
```

Submit for analysis
mythx --api-key `cat ../../.mythxKey` --config mythx.yml analyze