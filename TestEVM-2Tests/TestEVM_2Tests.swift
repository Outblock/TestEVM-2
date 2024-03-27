//
//  TestEVM_2Tests.swift
//  TestEVM-2Tests
//
//  Created by Hao Fu on 21/3/2024.
//

import XCTest
@testable import TestEVM_2
import WalletCore
import web3swift
import Web3Core
import Flow
import BigInt


final class TestEVM_2Tests: XCTestCase {
    
    var provider: Web3HttpProvider?
    var web3: Web3?
    var hdWallet: HDWallet!
    let address = Flow.Address(hex: "0xc3f180fad698d157")
    let ethAddress = EthereumAddress("0x000000000000000000000002a7D95998765430e7")!
    
    let magicValue = "0x1626ba7e"
    
    override func setUp() async throws {
        provider = try! await Web3HttpProvider(url: URL(string: "https://previewnet.evm.nodes.onflow.org")!, network: .Custom(networkID: 646))
        web3 = Web3(provider: provider!)
        flow.configure(chainID: .custom(name: "previewnet", transport: .HTTP(URL(string: "https://rest-previewnet.onflow.org")!)))
        hdWallet = HDWallet(mnemonic: "marriage pipe hamster army often include biology banana nose clutch damage helmet", passphrase: "")!
    }
    
    func testExample() async throws {
        let code = try! await web3!.eth.code(for: EthereumAddress.init("0x000000000000000000000002a48e1e98cbff3194")!)
        print(code)
    }
    
    func testQueryEBMAddress() async throws {
        let result = try! await flow.executeScriptAtLatestBlock(cadence: """
                import EVM from 0xb6763b4399a888c8

                access(all)
                fun main(address: Address): String {
                    let account = getAuthAccount<auth(Storage) &Account>(address)

                    let coa = account.storage.borrow<&EVM.CadenceOwnedAccount>(
                        from: /storage/evm
                    ) ?? panic("Could not borrow reference to the COA!")
                    
                    let coaAddr = coa.address()

                    let addrByte: [UInt8] = []

                    for byte in coaAddr.bytes {
                        addrByte.append(byte)
                    }
                    
                    // return 000000000000000000000002ef9b0732eeaa65dc  (hexEncodedAddress)
                    return String.encodeHex(addrByte)
                }
                   
                """, arguments: [.address(address)])
        
        let evmAddress: String = try! result.decode()
        print(evmAddress)
    }
    
    func testCreateEVMAccount() async throws {
        
        //"0x000000000000000000000002a7D95998765430e7"
        let signer = Signer(address: address, hdWallet: hdWallet)
        let txId = try await flow.sendTransaction(signers: [signer]) {
            cadence {
                """
                import FungibleToken from 0xa0225e7000ac82a9
                import FlowToken from 0x4445e7ad11568276
                import EVM from 0xb6763b4399a888c8


                transaction(amount: UFix64) {
                    let sentVault: @FlowToken.Vault
                    let auth: auth(Storage) &Account

                    prepare(signer: auth(Storage) &Account) {
                        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                            from: /storage/flowTokenVault
                        ) ?? panic("Could not borrow reference to the owner's Vault!")

                        self.sentVault <- vaultRef.withdraw(amount: amount) as! @FlowToken.Vault
                        self.auth = signer
                    }

                    execute {
                        let account <- EVM.createCadenceOwnedAccount()
                        log(account.address())
                        account.deposit(from: <-self.sentVault)

                        log(account.balance())
                        self.auth.storage.save<@EVM.CadenceOwnedAccount>(<-account, to: StoragePath(identifier: "evm")!)
                    }
                }
                """
            }
            
            arguments {
                .init(value: .ufix64(0))
            }
            
            proposer {
                self.address
            }
            
            authorizers {
                self.address
            }
        }
        
        print("txID ====> \(txId.hex)")
    }
    
    func testSignMessage() async throws {
        let text = "this is a message"
        guard let textData = text.data(using: .utf8) else {
            return
        }
        
//        let textData = Data.randomBytes(length: 32)!
        let signableData = Flow.DomainTag.user.normalize + textData
        let pk = hdWallet.getKeyByCurve(curve: .secp256k1, derivationPath: flowPath)
        let hashed = Hash.sha256(data: signableData)
        let hashed2 = Hash.sha256(data: textData)
        let sig = pk.sign(digest: hashed, curve: .secp256k1)!.dropLast()
        
        let proof = COAOwnershipProof(keyIninces: [0], address: address.data, capabilityPath: "coa", signatures: [sig])
        let encoded = RLP.encode(proof.rlpList)!
        let contract = web3!.contract(coaABI, at: ethAddress)!
//        print(contract.contract.methods.keys)
        print("pubK ===> \(pk.getPublicKeySecp256k1(compressed: false).data.hexValue)")
        print("encoded ===> \(encoded.hexValue)")
        print("flow address ===> \(address)")
        print("coa address ===> \(ethAddress.address)")
//        print("orginal message ===> \(text)")
        print("message data ===> \(textData.hexString)")
        print("hashed message ===> \(hashed.hexString)")
        print("sig ===> \(sig.hexString)")
        print("encoded ===> \(encoded.hexString)")
        let read = contract.createReadOperation("isValidSignature", parameters: [hashed, encoded])!
//        read.transaction.from = ethAddress
        let response = try await read.callContractMethod()
        
        guard let data = response["0"] as? Data else {
            return
        }
        
        let verfy = pk.getPublicKeySecp256k1(compressed: false).verify(signature: sig, message: hashed)
        print("verfy ==> \(verfy)")
        
        print(response)
        print(data.hexValue)
    }
}
