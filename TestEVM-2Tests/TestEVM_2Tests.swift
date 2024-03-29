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
    
    var provider: Web3HttpProvider!
    var web3: Web3!
    var hdWallet: HDWallet!
    let address = Flow.Address(hex: "0xd962e1938ab387c8")
    let ethAddress = EthereumAddress("0x0000000000000000000000029a9d22fe53a8fc9f")!
    
    let magicValue = "0x1626ba7e"
    
    override func setUp() async throws {
        provider = try! await Web3HttpProvider(url: URL(string: "https://previewnet.evm.nodes.onflow.org")!, network: .Custom(networkID: 646))
        web3 = Web3(provider: provider)
        flow.configure(chainID: .custom(name: "previewnet", transport: .HTTP(URL(string: "https://rest-previewnet.onflow.org")!)))
        hdWallet = HDWallet(mnemonic: "kiwi erosion weather slam harvest move crumble zero juice steel start hotel", passphrase: "")!
    }
    
    func testExample() async throws {
        let code = try! await web3.eth.code(for: EthereumAddress.init("0x000000000000000000000002a48e1e98cbff3194")!)
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
                    let auth: auth(IssueStorageCapabilityController, IssueStorageCapabilityController, PublishCapability, SaveValue, UnpublishCapability) &Account

                    prepare(signer: auth(BorrowValue, IssueStorageCapabilityController, PublishCapability, SaveValue, UnpublishCapability) &Account) {
                        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(
                                from: /storage/flowTokenVault
                            ) ?? panic("Could not borrow reference to the owner's Vault!")

                        self.sentVault <- vaultRef.withdraw(amount: amount) as! @FlowToken.Vault
                        self.auth = signer
                    }

                    execute {
                        let coa <- EVM.createCadenceOwnedAccount()
                        coa.deposit(from: <-self.sentVault)

                        log(coa.balance().inFLOW())
                        let storagePath = StoragePath(identifier: "evm")!
                        let publicPath = PublicPath(identifier: "evm")!
                        self.auth.storage.save<@EVM.CadenceOwnedAccount>(<-coa, to: storagePath)
                        let addressableCap = self.auth.capabilities.storage.issue<&EVM.CadenceOwnedAccount>(storagePath)
                        self.auth.capabilities.unpublish(publicPath)
                        self.auth.capabilities.publish(addressableCap, at: publicPath)
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
        let hashedData = Hash.sha256(data: textData)
//        let signableData = Flow.DomainTag.user.rawValue.data(using: .utf8)! + textData
        let signableData = Flow.DomainTag.user.normalize + hashedData
        let pk = hdWallet.getKeyByCurve(curve: .secp256k1, derivationPath: flowPath)
        let hashed = Hash.sha256(data: signableData)
        let sig = pk.sign(digest: hashed, curve: .secp256k1)!.dropLast()
        
        let proof = COAOwnershipProof(keyIninces: [0], address: address.data, capabilityPath: "evm", signatures: [sig])
        let encoded = RLP.encode(proof.rlpList)!
        let contract = web3.contract(coaABI, at: ethAddress)!
//        print("pubK ===> \(pk.getPublicKeySecp256k1(compressed: false).data.hexValue)")
        print("flow address ===> \(pk.data.hexValue)")
        print("flow address ===> \(address)")
        print("coa address ===> \(ethAddress.address)")
//        print("orginal message ===> \(text)")
        print("message data ===> \(textData.hexString)")
        print("signableData message ===> \(signableData.hexString)")
        print("hashed message ===> \(hashed.hexString)")
        print("sig ===> \(sig.hexString)")
        print("encoded ===> \(encoded.hexString)")
        let read = contract.createReadOperation("isValidSignature", parameters: [hashedData, encoded])!
//        read.transaction.from = ethAddress
        let response = try await read.callContractMethod()
        
        guard let data = response["0"] as? Data else {
            return
        }
        
//        let verfy = pk.getPublicKeySecp256k1(compressed: false).verify(signature: sig, message: hashed)
//        print("verfy ==> \(verfy)")
        
        print(response)
        print(data.hexValue)
        
        XCTAssertEqual(data.hexValue.addHexPrefix(), magicValue)
        
        
        let result = try! await flow.executeScriptAtLatestBlock(cadence: """
        import EVM from 0xb6763b4399a888c8

        access(all)
        fun main(tx: [UInt8], coinbaseBytes: [UInt8; 20]) {
            let coinbase = EVM.EVMAddress(bytes: coinbaseBytes)
            EVM.run(tx: tx, coinbase: coinbase)
        }
        """, arguments: [
                .array(read.data!.map{ Flow.Cadence.FValue.uint8($0) }),
                .array(ethAddress.addressData.map{ Flow.Cadence.FValue.uint8($0) })
            ]
        )
        
        print(result)
        
    }
}
