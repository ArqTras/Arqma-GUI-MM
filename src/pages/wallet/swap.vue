<template>
  <q-page class="swap">
    <div class="q-pa-md">
      <div
        class="row justify-center items-center"
        style="font-size: 16px;"
      >
        <ul>
          <li>{{ $t('pages.wallet.swap.disclaimer1') }}</li>
          <li>{{ $t('pages.wallet.swap.disclaimer2') }}</li>
          <li>{{ $t('pages.wallet.swap.disclaimer3') }} {{ $t('pages.wallet.swap.disclaimer4') }}</li>
          <li>{{ $t('pages.wallet.swap.disclaimer5') }}</li>
        </ul>
      </div>
    </div>
    <template v-if="view_only">
      <div class="q-pa-md">
        {{ $t('pages.wallet.swap.view_only') }}
      </div>
    </template>
    <template v-else>
      <div class="q-pa-md">
        <div class="row justify-center items-center">
          <q-btn
            class="col-auto"
            color="positive"
            :label="connectButtonLabel"
            @click="connectWallet()"
          />&nbsp;&nbsp;

          <q-btn
            class="col-auto"
            :disable="disconnected"
            color="positive"
            :label="$t('pages.wallet.swap.add_asset_to_wallet')"
            @click="requestAddAsset()"
          />&nbsp;&nbsp;
        </div>

        <div class="row justify-center items-center">
          <div class="col-2 q-px-sm">
            <arqmaField
              :label="$t('pages.wallet.swap.network')"
              class="network"
            >
              {{ selectedNetwork.name
              }}<q-btn-dropdown
                :disable="disconnected"
                class="remote-dropdown"
                flat
                transition-show="flip-up"
                transition-hide="flip-down"
              >
                <q-list
                  link
                  dark
                  no-border
                >
                  <q-item
                    v-for="option in networks"
                    :key="option.code"
                    v-close-popup
                    clickable
                    @click="setNetwork(option)"
                  >
                    <q-item-section>
                      <q-item-label>
                        {{ option.name }}
                      </q-item-label>
                    </q-item-section>
                  </q-item>
                </q-list>
              </q-btn-dropdown>
            </arqmaField>
          </div>
        </div>
        <div class="row q-pa-md justify-center items-center">
          <span>
            <Formatarqma
              :amount="newTokenTx.balance"
              :as-wei="true"
            /> {{ selectedNetwork.symbol }}
          </span>
        </div>

        <q-tabs
          v-model="tab"
          align="justify"
          indicator-color="positive"
          dense
        >
          <q-tab name="native">
            <div class="row justify-center items-center">
              <span class="transfer-text">Native</span><q-icon
                color="positive"
                size="4em"
                name="arrow_right_alt"
              /><span class="transfer-text">Wrapped</span>
            </div>
          </q-tab>

          <q-tab name="wrapped">
            <div class="row justify-center items-center">
              <span class="transfer-text">Wrapped</span><q-icon
                color="positive"
                size="4em"
                name="arrow_right_alt"
              /><span class="transfer-text">Native</span>
            </div>
          </q-tab>
        </q-tabs>

        <q-tab-panels
          v-model="tab"
          style="background-color: transparent;"
          animated
        >
          <q-tab-panel
            v-model="tab"
            name="native"
          >
            <div class="row gutter-md">
              <div class="col-2 q-px-sm">
                <arqmaField
                  :label="`${t('pages.wallet.swap.amount_of_xeq_to_swap')} ${selectedNetwork.symbol}`"
                  :error="v$.amount.$error"
                >
                  <q-input
                    v-model="newTx.amount"
                    :dark="theme == 'dark'"
                    type="number"
                    min="0"
                    :max="unlocked_balance / 1e9"
                    placeholder="0"
                    borderless
                    dense
                    @blur="v$.amount.$validate()"
                  />
                  <q-btn
                    color="positive"
                    :text-color="theme == 'dark' ? 'white' : 'dark'"
                    @click="
                      newTx.amount = unlocked_balance / 1e9;
                    "
                  >
                    All
                  </q-btn>
                </arqmaField>
              </div>

              <div class="col-9 q-px-sm">
                <arqmaField
                  :label="`${selectedNetwork.name} ${t('pages.wallet.swap.address')}`"
                  :error="v$.memo.$error"
                >
                  <q-input
                    v-model="newTx.memo"
                    :dark="theme == 'dark'"
                    :placeholder="'0x...'"
                    borderless
                    dense
                    :clearable="true"
                    @blur="v$.memo.$validate()"
                  />
                </arqmaField>
              </div>
              <div
                class="col-1 q-px-sm"
                style="padding-top: 35px;"
              >
                <q-btn
                  :disable="!is_able_to_send"
                  color="positive"
                  :label="$t('pages.wallet.swap.send')"
                  @click="send()"
                />
              </div>
            </div>

            <div class="scroller">
              <div
                :visible="false"
                class="fit column"
              >
                <SwapListTabular @complete-exchange="acceptTransfer" />
              </div>
            </div>
          </q-tab-panel>

          <q-tab-panel
            v-model="tab"
            name="wrapped"
          >
            <div class="row gutter-md">
              <div class="col-2 q-px-sm">
                <arqmaField
                  :label="`${t('pages.wallet.swap.amount_of')} eXEQ`"
                  :error="e$.tokenAmount.$error"
                >
                  <q-input
                    v-model="newTokenTx.tokenAmount"
                    :dark="theme == 'dark'"
                    type="number"
                    min="1"
                    :max="newTokenTx.balance"
                    placeholder="0"
                    borderless
                    dense
                    @blur="e$.tokenAmount.$validate()"
                  />
                  <q-btn
                    color="positive"
                    :text-color="theme == 'dark' ? 'white' : 'dark'"
                    @click="newTokenTx.tokenAmount = newTokenTx.balance"
                  >
                    All
                  </q-btn>
                </arqmaField>
              </div>
              <div class="col-4 q-px-sm">
                <arqmaField
                  :label="`${selectedNetwork.name} ${t('pages.wallet.swap.address')}`"
                  :error="e$.tokenAddress.$error"
                >
                  <q-input
                    v-model="newTokenTx.tokenAddress"
                    :dark="theme == 'dark'"
                    :placeholder="'0x...'"
                    borderless
                    dense
                    :clearable="true"
                    @blur="e$.tokenAddress.$validate()"
                  />
                </arqmaField>
              </div>
              <div class="col-5 q-px-sm">
                <arqmaField
                  :label="`ARQ ${t('pages.wallet.swap.address')}`"
                  :error="e$.address.$error"
                >
                  <q-input
                    v-model="newTokenTx.address"
                    :dark="theme == 'dark'"
                    :placeholder="'Tw...'"
                    borderless
                    dense
                    :clearable="true"
                    @blur="e$.address.$validate()"
                  />
                </arqmaField>
              </div>
              <div
                class="col-1 q-pa-md"
                style="padding-top: 35px;"
              >
                <q-btn
                  class="col-auto"
                  :disable="disconnected"
                  color="positive"
                  :label="$t('pages.wallet.swap.send')"
                  @click="requestToExchangeTokens()"
                />
              </div>
            </div>
          </q-tab-panel>
        </q-tab-panels>
      </div>

      <q-dialog
        v-model="confirmXEQSend"
        class="column"
        persistent
        transition-show="flip-up"
        transition-hide="flip-down"
      >
        <q-card
          :dark="theme == 'dark'"
          style="min-width: 300px;"
        >
          <q-card-section class="column justify-center items-center">
            <h5>CONFIRM AMOUNT</h5>
            <arqmaField :error="v$.amount.$error">
              <q-input
                v-model="newTx.amount"
                :dark="theme == 'dark'"
                type="number"
                min="0"
                :max="unlocked_balance / 1e9"
                placeholder="0"
                suffix="xeq"
                borderless
                dense
                @blur="v$.amount.$validate()"
              />
            </arqmaField>
            <h5>CONFIRM ADDRESS</h5>
            <arqmaField>
              <q-input
                v-model="newTx.memo"
                :dark="theme == 'dark'"
                :placeholder="'0x...'"
                borderless
                dense
                @blur="v$.memo.$validate"
              />
            </arqmaField>
          </q-card-section>
          <q-card-actions align="right">
            <q-btn
              class="sendBtn"
              color="positive"
              label="SEND"
              @click="(confirmXEQSend = false), send()"
            />
          </q-card-actions>
        </q-card>
      </q-dialog>

      <q-dialog
        v-model="TokenToNativeSend"
        persistent
        class="column"
        transition-show="flip-up"
        transition-hide="flip-down"
      >
        <q-card
          :dark="theme == 'dark'"
          style="min-width: 300px;"
        >
          <q-card-section class="column justify-center items-center">
            <h5>{{ transaction_status }}</h5>
          </q-card-section>
          <q-card-section
            v-if="showCopy"
            class="column justify-center items-center"
            side
          >
            <span class="cursor-pointer q-hoverable">{{ transactionHash }}</span>
            <q-btn
              ref="copy"
              color="primary"
              padding="xs"
              size="sm"
              icon="file_copy"
              @click="copyAddress"
            >
              <q-tooltip
                anchor="center left"
                self="center right"
                :offset="[5, 10]"
              >
                {{ $t('components.address_header.copy_address') }}
              </q-tooltip>
            </q-btn>
            <q-menu context-menu>
              <q-list
                separator
                class="context-menu"
              >
                <q-item
                  v-close-popup
                  clickable
                  @click="copyAddress()"
                >
                  <q-item-section>{{ $t('components.address_header.copy_address') }}</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="openExplorer()"
                >
                  <q-item-section>
                    {{ $t('components.pool_list_tabular.view_on_explorer')
                    }}
                  </q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-card-section>
          <q-card-section
            v-else
            class="column justify-center items-center"
          >
            <q-spinner-orbit
              color="positive"
              size="8em"
              style="margin-bottom: 2em;"
            />
          </q-card-section>
          <q-card-actions
            v-if="showCopy"
            align="right"
          >
            <q-btn
              class="sendBtn"
              color="positive"
              label="CLOSE"
              @click="(TokenToNativeSend = false)"
            />
          </q-card-actions>
        </q-card>
      </q-dialog>

      <q-dialog
        v-model="NativeToTokenSend"
        persistent
        class="column"
        transition-show="flip-up"
        transition-hide="flip-down"
      >
        <q-card
          :dark="theme == 'dark'"
          style="min-width: 300px;"
        >
          <q-card-section class="column justify-center items-center">
            <h5>{{ transaction_status }}</h5>
          </q-card-section>
          <q-card-section
            v-if="showCopy"
            class="column justify-center items-center"
            side
          >
            <span class="cursor-pointer q-hoverable">{{ transactionHash }}</span>
            <q-btn
              ref="copy"
              color="primary"
              padding="xs"
              size="sm"
              icon="file_copy"
              @click="copyAddress"
            >
              <q-tooltip
                anchor="center left"
                self="center right"
                :offset="[5, 10]"
              >
                {{ $t('components.address_header.copy_address') }}
              </q-tooltip>
            </q-btn>
            <q-menu context-menu>
              <q-list
                separator
                class="context-menu"
              >
                <q-item
                  v-close-popup
                  clickable
                  @click="copyAddress()"
                >
                  <q-item-section>{{ $t('components.address_header.copy_address') }}</q-item-section>
                </q-item>
                <q-item
                  v-close-popup
                  clickable
                  @click="openExplorer()"
                >
                  <q-item-section>
                    {{ $t('components.pool_list_tabular.view_on_explorer')
                    }}
                  </q-item-section>
                </q-item>
              </q-list>
            </q-menu>
          </q-card-section>
          <q-card-section
            v-else
            class="column justify-center items-center"
          >
            <q-spinner-orbit
              color="positive"
              size="8em"
              style="margin-bottom: 2em;"
            />
          </q-card-section>
          <q-card-actions
            v-if="showCopy"
            align="right"
          >
            <q-btn
              class="sendBtn"
              color="positive"
              label="CLOSE"
              @click="(NativeToTokenSend = false)"
            />
          </q-card-actions>
        </q-card>
      </q-dialog>
    </template>
  </q-page>
</template>

<script>

import { computed, defineComponent, onMounted, ref, watch, reactive, onBeforeUnmount, onBeforeMount, nextTick } from "vue"
import { useStore } from "vuex"
import { useQuasar, extend } from "quasar"
import { useVuelidate } from "@vuelidate/core"
import { required, decimal } from "@vuelidate/validators"
import { greater_than_zero, payment_id } from "src/validators/common"
import arqmaField from "components/arqma_field"
import Formatarqma from "components/format_arqma"
import { usePasswordConfirmation } from "src/composables/wallet_password"
import { useI18n } from "vue-i18n"
import SwapListTabular from "components/swap_list_tabular"

import { MetaMaskSDK } from "@metamask/sdk"
import { Web3 } from "web3"
import { useDebounce } from "src/composables/debounce"

export default defineComponent({
  components: {
    arqmaField,
    Formatarqma,
    SwapListTabular
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()
    const { debounce } = useDebounce()
    const copy = ref(null)
    const { showPasswordConfirmation } = usePasswordConfirmation()
    const TokenToNativeSend = ref(false)
    const NativeToTokenSend = ref(false)
    const confirmXEQSend = ref(false)
    const sending = ref(false)
    const connectButtonLabel = ref("")
    const transaction_status = ref("")
    const showCopy = ref(false)
    const transactionHash = ref("")
    const tab = ref("native")
    const isDevelopment = ref(false)
    let ethereum
    const disconnected = ref(true)
    // eslint-disable-next-line
        const tokenABI = [{ "inputs": [{ "internalType": "string", "name": "name", "type": "string" }, { "internalType": "string", "name": "symbol", "type": "string" }, { "internalType": "address", "name": "initialOwner", "type": "address" }, { "internalType": "uint8", "name": "decimals", "type": "uint8" }], "stateMutability": "nonpayable", "type": "constructor" }, { "inputs": [], "name": "ECDSAInvalidSignature", "type": "error" }, { "inputs": [{ "internalType": "uint256", "name": "length", "type": "uint256" }], "name": "ECDSAInvalidSignatureLength", "type": "error" }, { "inputs": [{ "internalType": "bytes32", "name": "s", "type": "bytes32" }], "name": "ECDSAInvalidSignatureS", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "spender", "type": "address" }, { "internalType": "uint256", "name": "allowance", "type": "uint256" }, { "internalType": "uint256", "name": "needed", "type": "uint256" }], "name": "ERC20InsufficientAllowance", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "sender", "type": "address" }, { "internalType": "uint256", "name": "balance", "type": "uint256" }, { "internalType": "uint256", "name": "needed", "type": "uint256" }], "name": "ERC20InsufficientBalance", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "approver", "type": "address" }], "name": "ERC20InvalidApprover", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "receiver", "type": "address" }], "name": "ERC20InvalidReceiver", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "sender", "type": "address" }], "name": "ERC20InvalidSender", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "spender", "type": "address" }], "name": "ERC20InvalidSpender", "type": "error" }, { "inputs": [], "name": "InvalidShortString", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "owner", "type": "address" }], "name": "OwnableInvalidOwner", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "OwnableUnauthorizedAccount", "type": "error" }, { "inputs": [{ "internalType": "string", "name": "str", "type": "string" }], "name": "StringTooLong", "type": "error" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "owner", "type": "address" }, { "indexed": true, "internalType": "address", "name": "spender", "type": "address" }, { "indexed": false, "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "Approval", "type": "event" }, { "anonymous": false, "inputs": [], "name": "EIP712DomainChanged", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "previousOwner", "type": "address" }, { "indexed": true, "internalType": "address", "name": "newOwner", "type": "address" }], "name": "OwnershipTransferred", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "from", "type": "address" }, { "indexed": true, "internalType": "address", "name": "to", "type": "address" }, { "indexed": false, "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "Transfer", "type": "event" }, { "inputs": [{ "internalType": "address", "name": "owner", "type": "address" }, { "internalType": "address", "name": "spender", "type": "address" }], "name": "allowance", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "spender", "type": "address" }, { "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "approve", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "balanceOf", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "burn", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "burn", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }, { "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "burnFrom", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "decimals", "outputs": [{ "internalType": "uint8", "name": "", "type": "uint8" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "eip712Domain", "outputs": [{ "internalType": "bytes1", "name": "fields", "type": "bytes1" }, { "internalType": "string", "name": "name", "type": "string" }, { "internalType": "string", "name": "version", "type": "string" }, { "internalType": "uint256", "name": "chainId", "type": "uint256" }, { "internalType": "address", "name": "verifyingContract", "type": "address" }, { "internalType": "bytes32", "name": "salt", "type": "bytes32" }, { "internalType": "uint256[]", "name": "extensions", "type": "uint256[]" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "to", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "mint", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "to", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }, { "internalType": "uint256", "name": "nonce", "type": "uint256" }, { "internalType": "uint256", "name": "deadline", "type": "uint256" }, { "internalType": "bytes", "name": "signature", "type": "bytes" }], "name": "mintTokens", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "name", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "", "type": "address" }], "name": "nonces", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "owner", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "renounceOwnership", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "symbol", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "totalSupply", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "to", "type": "address" }, { "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "transfer", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "from", "type": "address" }, { "internalType": "address", "name": "to", "type": "address" }, { "internalType": "uint256", "name": "value", "type": "uint256" }], "name": "transferFrom", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "newOwner", "type": "address" }], "name": "transferOwnership", "outputs": [], "stateMutability": "nonpayable", "type": "function" }]
    // eslint-disable-next-line
        const bridgeABI = [{ "inputs": [{ "internalType": "address", "name": "initialOwner", "type": "address" }], "stateMutability": "nonpayable", "type": "constructor" }, { "inputs": [], "name": "ECDSAInvalidSignature", "type": "error" }, { "inputs": [{ "internalType": "uint256", "name": "length", "type": "uint256" }], "name": "ECDSAInvalidSignatureLength", "type": "error" }, { "inputs": [{ "internalType": "bytes32", "name": "s", "type": "bytes32" }], "name": "ECDSAInvalidSignatureS", "type": "error" }, { "inputs": [], "name": "InvalidShortString", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "owner", "type": "address" }], "name": "OwnableInvalidOwner", "type": "error" }, { "inputs": [{ "internalType": "address", "name": "account", "type": "address" }], "name": "OwnableUnauthorizedAccount", "type": "error" }, { "inputs": [{ "internalType": "string", "name": "str", "type": "string" }], "name": "StringTooLong", "type": "error" }, { "anonymous": false, "inputs": [], "name": "EIP712DomainChanged", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": false, "internalType": "uint256", "name": "_amount", "type": "uint256" }], "name": "FeeChanged", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": false, "internalType": "bool", "name": "tokenWallet", "type": "bool" }], "name": "FeeWalletChanged", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "previousOwner", "type": "address" }, { "indexed": true, "internalType": "address", "name": "newOwner", "type": "address" }], "name": "OwnershipTransferred", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "_address", "type": "address" }, { "indexed": false, "internalType": "string", "name": "_newSymbol", "type": "string" }, { "indexed": false, "internalType": "uint256", "name": "_decimals", "type": "uint256" }], "name": "WrappedCreated", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "_to", "type": "address" }, { "indexed": true, "internalType": "uint32", "name": "_blockNumber", "type": "uint32" }, { "indexed": false, "internalType": "bytes", "name": "_signature", "type": "bytes" }], "name": "XNative4Wrapped", "type": "event" }, { "anonymous": false, "inputs": [{ "indexed": true, "internalType": "address", "name": "_from", "type": "address" }, { "indexed": false, "internalType": "uint256", "name": "_amount", "type": "uint256" }, { "indexed": false, "internalType": "string", "name": "_to", "type": "string" }], "name": "XWrapped4Native", "type": "event" }, { "inputs": [{ "internalType": "address", "name": "receiver", "type": "address" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }, { "internalType": "uint32", "name": "blockNumber", "type": "uint32" }, { "internalType": "bytes32", "name": "blockHash", "type": "bytes32" }, { "internalType": "bytes32", "name": "transactionHash", "type": "bytes32" }, { "internalType": "uint32", "name": "logIndex", "type": "uint32" }, { "internalType": "uint256", "name": "nonce", "type": "uint256" }, { "internalType": "uint256", "name": "deadline", "type": "uint256" }, { "internalType": "bytes", "name": "signature", "type": "bytes" }], "name": "acceptTransfer", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "eip712Domain", "outputs": [{ "internalType": "bytes1", "name": "fields", "type": "bytes1" }, { "internalType": "string", "name": "name", "type": "string" }, { "internalType": "string", "name": "version", "type": "string" }, { "internalType": "uint256", "name": "chainId", "type": "uint256" }, { "internalType": "address", "name": "verifyingContract", "type": "address" }, { "internalType": "bytes32", "name": "salt", "type": "bytes32" }, { "internalType": "uint256[]", "name": "extensions", "type": "uint256[]" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "string", "name": "to", "type": "string" }, { "internalType": "uint256", "name": "amount", "type": "uint256" }, { "internalType": "uint256", "name": "nonce", "type": "uint256" }, { "internalType": "uint256", "name": "deadline", "type": "uint256" }, { "internalType": "bytes", "name": "signature", "type": "bytes" }], "name": "exchangeTokens", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "exeq", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "feePercentageDivider", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "getFeePercentage", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "getPrefix", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "_factory", "type": "address" }, { "internalType": "string", "name": "_symbolPrefix", "type": "string" }], "name": "init", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "", "type": "address" }], "name": "nonces", "outputs": [{ "internalType": "uint256", "name": "", "type": "uint256" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "owner", "outputs": [{ "internalType": "address", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "bytes32", "name": "", "type": "bytes32" }], "name": "processed", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "renounceOwnership", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "uint256", "name": "amount", "type": "uint256" }], "name": "setFeePercentage", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [{ "internalType": "bool", "name": "tokenWallet", "type": "bool" }], "name": "setFeeWallet", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "symbolPrefix", "outputs": [{ "internalType": "string", "name": "", "type": "string" }], "stateMutability": "view", "type": "function" }, { "inputs": [], "name": "tokenFactory", "outputs": [{ "internalType": "contract IBridgeTokenFactory", "name": "", "type": "address" }], "stateMutability": "view", "type": "function" }, { "inputs": [{ "internalType": "address", "name": "newOwner", "type": "address" }], "name": "transferOwnership", "outputs": [], "stateMutability": "nonpayable", "type": "function" }, { "inputs": [], "name": "usingTokenWallet", "outputs": [{ "internalType": "bool", "name": "", "type": "bool" }], "stateMutability": "view", "type": "function" }]

    const newTokenTx = reactive({
      tokenAmount: 0,
      tokenAddress: "",
      address: "",
      balance: 0
    })

    const newTx = reactive({
      amount: 0,
      address: "Tw1WW1jYkS3144DkXTDQgg6j2fDk28KuDeYdQZb91UvnZ462yRExJz2h7k116wXbRp4JhcYyfb3PabpTuaRX9DiG2U5kGJ6wS",
      network: {
        name: "ETH",
        code: 0
      },
      memo: "",
      currency: 0
    })

    const selectedNetwork = ref({
      name: "ETH",
      symbol: "eXEQ",
      code: 0
    })

    const networks = ref([
      {
        name: "ETH",
        symbol: "eXEQ",
        code: 0
      },
      //   {
      //     name: "AVAX",
      //     symbol: "aXEQ",
      //     code: 1
      //   },
      //   {
      //     name: "MATIC",
      //     symbol: "pXEQ",
      //     code: 2
      //   },
      {
        name: "BNB",
        symbol: "bXEQ",
        code: 3
      }
    ])

    const rules = computed(() => {
      return {
        amount: {
          required,
          decimal,
          greater_than_zero
        },
        tokenAddress: {
          required
        },
        address: { required },
        network: { required },
        memo: {
          required
        }
      }
    })

    const erules = computed(() => {
      return {
        tokenAmount: {
          required,
          greater_than_zero
        },
        tokenAddress: {
          required
        },
        address: {
          required
        }
      }
    })

    const v$ = useVuelidate(rules, newTx)
    const e$ = useVuelidate(erules, newTokenTx)

    const maxHeight = ref(`${Number(document.documentElement.clientHeight) - 600}px`)

    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const view_only = computed(() => $store.state.gateway.wallet.info.view_only)
    const unlocked_balance = computed(() => $store.state.gateway.wallet.info.unlocked_balance)
    const tx_status = computed((state) => $store.state.gateway.tx_status)
    const stake_status = computed(() => $store.state.gateway.service_node_status.stake)
    const is_ready = computed(() => {
      return $store.getters["gateway/isReady"]
    })
    const ethereum_network = computed(() => $store.getters["gateway/ethereum_network"])

    const is_able_to_send = computed(() => {
      return $store.getters["gateway/isAbleToSend"]
    })

    const address_placeholder = computed(() => {
      const wallet = $store.state.gateway.wallet.info.value
      const prefix = (wallet && wallet.address && wallet.address[0]) || "L"
      return `${prefix}..`
    })

    // Watchers
    const tx_statusWatcher = watch(tx_status, (newVal, oldVal) => {
      try {
        if (newVal.code === oldVal.code) return
        const { code, message } = newVal
        switch (code) {
          case 200:
            $q
              .dialog({
                title: t("pages.wallet.swap.tx_status_title"),
                message,
                ok: {
                  label: t("pages.wallet.swap.tx_status_ok_label"),
                  color: "positive"
                },
                cancel: {
                  flat: true,
                  label: t("pages.wallet.swap.tx_status_cancel_label"),
                  color: "red"
                },
                transitionShow: "flip-up",
                transitionHide: "flip-down",
                dark: theme.value === "dark",
                color: theme.value === "dark" ? "white" : "dark"
              })
              .onOk(() => {
                api.send("wallet", "relay_transfer", {})
                $q.notify({
                  type: "positive",
                  timeout: 3000,
                  message // : t(message)
                })
              })
              .onDismiss(() => { })
              .onCancel(() => {
                api.send("wallet", "cancel_stake", {})
                $q.notify({
                  type: "positive",
                  timeout: 3000,
                  message: t("pages.wallet.swap.tx_status_relay_transfer_cancel_message")
                })
              })

            break
          case -200:
            $q.notify({
              type: "negative",
              timeout: 3000,
              message // : t(message)
            })
            break
        }
      } catch (error) {
        api.error("/pages/wallet/swap", "tx_statusWatcher", error.stack || error)
      }
    })

    let sdk = null
    // Hooks
    onMounted(async () => {
      isDevelopment.value = await api.isDevelopment()
      connectButtonLabel.value = t("pages.wallet.swap.connect_wallet")
      sdk = new MetaMaskSDK({
        shouldShimWeb3: false,
        storage: {
          enabled: true
        },
        dappMetadata: {
          name: "Arqma Electron Wallet",
          url: "https://arqma.com"
        }
      })
    })

    const debouncedFn = debounce(() => {
      const clientHeight = document.documentElement.clientHeight
      maxHeight.value = `${Number(clientHeight) - 600}px`
    }, 500)

    onBeforeMount(() => {
      try {
        window.addEventListener("resize", debouncedFn)
      } catch (error) {
        api.error("/pages/wallet/swap", "onBeforeMounted", error.stack || error)
      }
    })

    onBeforeUnmount(() => {
      try {
        if (!disconnected.value && sdk) {
          sdk.terminate()
        }
      } catch (error) {
        api.error("/pages/wallet/swap", "onBeforeUnmount", error.stack || error)
      }
      try {
        const clientHeight = document.documentElement.clientHeight
        maxHeight.value = `${Number(clientHeight) - 600}px`
        window.removeEventListener("resize", debouncedFn)
        api.send("wallet", "unsubscribe_for_signature_data", {})
      } catch (error) {
        api.error("/pages/wallet/swap", "onBeforeUnmount", error.stack || error)
      }
    })

    // Methods
    const setNetwork = async (network) => {
      try {
        newTx.network = network
        selectedNetwork.value = network
        await switchChain()
      } catch (error) {
        await api.error("/pages/wallet/swap", "setNetwork", error.stack || error)
      }
    }

    const copyAddress = async () => {
      try {
        copy.value.$el.blur()
        api.writeText(transactionHash.value)
      } catch (error) {
        await api.error("/pages/wallet/swap", "copyAddress", error.stack || error)
      }
    }

    const openExplorer = async () => {
      try {
        const chain = getChain()
        api.send("core", "open_explorer", { type: "swap_tx_id", explorer: chain.explorer, id: transactionHash.value })
      } catch (error) {
        await api.error("/pages/wallet/swap", "openExplorer", error.stack || error)
      }
    }

    const getAmount = async () => {
      try {
        return newTx.amount
      } catch (error) {
        await api.error("/pages/wallet/swap", "getAmount", error.stack || error)
      }
    }

    const send = async () => {
      try {
        newTx.network = selectedNetwork.value

        await v$.value.$validate()

        if (v$.value.amount.$error && v$.value.memo.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_amount_and_address")
          })
          return
        }

        if (v$.value.amount.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_amount")
          })
          return
        }

        if (v$.value.memo.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_address")
          })
          return
        }

        if (newTx.amount > unlocked_balance.value / 1e9) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.not_enough_unlocked_balance")
          })
          return
        }

        const title = t("pages.wallet.swap.show_password_confirmation_title").replace("eXEQ", selectedNetwork.value.symbol)
        const dialog = await showPasswordConfirmation({
          title,
          noPasswordMessage: t("pages.wallet.swap.show_password_confirmation_message"),
          ok: {
            label: t("pages.wallet.swap.show_password_confirmation_ok_label"),
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })
        dialog.onOk((password) => {
          $store.commit("gateway/set_tx_status", {
            code: 1,
            message: t("pages.wallet.swap.show_password_confirmation_ok_message"),
            sending: true
          })
          password = password || ""
          const chain = getChain()
          const copy = extend(true, {}, newTx, { password }, { network: { code: newTx.network.code }, address: chain.governance })
          api.send("wallet", "transfer", copy)
        })
          .onDismiss(() => { })
          .onCancel(() => { })
      } catch (error) {
        await api.error("/pages/wallet/swap", "send", error.stack || error)
      }
    }

    const connectWallet = async () => {
      try {
        // await sdk.init()
        if (sdk) {
          if (!disconnected.value) {
            api.send("wallet", "unsubscribe_for_signature_data", {})
            sdk.terminate()
          } else {
            const accounts = await sdk.connect()
            ethereum = sdk.getProvider()

            // const accounts = await (await ethereum.request({ method: "eth_requestAccounts" }))
            // if (accounts.length === 0) {
            //   disconnected.value = true
            //   return
            // }
            disconnected.value = false
            connectButtonLabel.value = t("pages.wallet.swap.connected_wallet")
            newTx.memo = accounts?.[0]
            newTokenTx.tokenAddress = accounts?.[0]
            newTokenTx.balance = await getTokenBalance()
            await api.send("wallet", "subscribe_for_signature_data", { ethereumAddress: newTx.memo.toLowerCase() })

            ethereum.on("connect", () => {
              disconnected.value = false
              connectButtonLabel.value = t("pages.wallet.swap.connected_wallet")
            })

            ethereum.on("disconnect", () => {
              disconnected.value = true
              connectButtonLabel.value = t("pages.wallet.swap.connect_wallet")
            })

            ethereum.on("chainChanged", async (chain) => {
              const indexOfChain = ethereum_network.value.findIndex(f => f.id === Number(chain))
              if (indexOfChain >= 0) {
                await setNetwork(networks.value[indexOfChain])
                newTokenTx.balance = await getTokenBalance()
                newTokenTx.tokenAmount = 0
              } else {
                newTokenTx.balance = 0
                newTokenTx.tokenAmount = 0
              }
            })

            ethereum.on("accountsChanged", async (accounts) => {
              if (accounts.length === 0) {
                newTokenTx.balance = 0
                newTokenTx.tokenAmount = 0
                disconnected.value = true
                return
              }
              disconnected.value = false
              newTx.memo = accounts?.[0]
              newTokenTx.tokenAddress = accounts?.[0]
              newTokenTx.balance = await getTokenBalance()
              newTokenTx.tokenAmount = 0
            })
          }
        }
      } catch (error) {
        await api.error("/pages/wallet/swap", "connectWallet", "Failed")
      }
    }

    const getTokenBalance = async () => {
      try {
        const web3 = new Web3(ethereum)
        const chain = getChain()
        if (chain) {
          const tokenContract = new web3.eth.Contract(tokenABI, chain.token_address)

          const balance = await tokenContract.methods.balanceOf(newTokenTx.tokenAddress).call()
          return Number(Web3.utils.fromWei(balance, "ether"))
        }
        return 0
      } catch (error) {
        await api.error("/pages/wallet/swap", "getTokenBalance", error.stack || error)
      }
      return 0
    }

    const getNonce = async (web3, ABI, address) => {
      try {
        const contract = new web3.eth.Contract(ABI, address)
        const nonce = await contract.methods.nonces(newTokenTx.tokenAddress).call()
        return nonce
      } catch (error) {
        await api.error("/pages/wallet/swap", "getNonce", error.stack || error)
      }
      return 0
    }

    const requestToExchangeTokens = async () => {
      try {
        await e$.value.$validate()
        if (e$.value.tokenAmount.$error && e$.value.tokenAddress.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_amount_and_address")
          })
          return
        }

        if (e$.value.tokenAmount.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_amount")
          })
          return
        }

        if (newTokenTx.tokenAmount > newTokenTx.balance) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.request_exceeds_balance")
          })
          return
        }

        if (e$.value.address.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_address")
          })
          return
        }

        if (e$.value.tokenAddress.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.invalid_address")
          })
          return
        }

        const title = t("pages.wallet.swap.show_password_confirmation_title_swaps").replace("eXEQ", selectedNetwork.value.symbol)
        const dialog = await showPasswordConfirmation({
          title,
          noPasswordMessage: t("pages.wallet.swap.show_password_confirmation_message"),
          ok: {
            label: t("pages.wallet.swap.show_password_confirmation_ok_label"),
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })
        dialog.onOk(async (password) => {
          const web3 = new Web3(ethereum)
          const chain = getChain()
          const tokenContract = new web3.eth.Contract(tokenABI, chain.token_address)
          try {
            showCopy.value = false
            TokenToNativeSend.value = true
            transactionHash.value = ""
            transaction_status.value = t("pages.wallet.swap.requesting_approval") // "Requesting Approval"
            await tokenContract.methods.approve(chain.bridge_address, web3.utils.toWei(newTokenTx.tokenAmount, "ether")).send({ from: newTokenTx.tokenAddress })
            transaction_status.value = t("pages.wallet.swap.approved") // "Approved"
            await nextTick()
            await confirmExchangeTokens(web3, chain)
          } catch (error) {
            TokenToNativeSend.value = false
            if (error.error?.code === 4001) {
              $q.notify({
                type: "negative",
                timeout: 3000,
                message: error.error.message
              })
            } else {
              $q.notify({
                type: "negative",
                timeout: 3000,
                message: t("pages.wallet.swap.error_occured_check_logs")
              })
              await api.error("/pages/wallet/swap", "requestToExchangeTokens", error.stack || error)
            }
          }
        })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        TokenToNativeSend.value = false
        await api.error("/pages/wallet/swap", "requestToExchangeTokens", error.stack || error)
      }
    }

    const confirmExchangeTokens = async (web3, chain) => {
      try {
        const { nonce, deadline, signature } = await buildSignature(web3)
        const bridgeContract = new web3.eth.Contract(bridgeABI, chain.bridge_address)
        transaction_status.value = t("pages.wallet.swap.requesting_transfer") // "Requesting Transfer"
        const data = await bridgeContract.methods.exchangeTokens(newTokenTx.address, web3.utils.toWei(newTokenTx.tokenAmount, "ether"), nonce, deadline, signature).send({ from: newTokenTx.tokenAddress })
        transactionHash.value = data.transactionHash
        transaction_status.value = t("pages.wallet.swap.transaction_completed") // "Transaction Completed"
        showCopy.value = true
        newTokenTx.tokenAmount = 0
        e$.value.$reset()
      } catch (error) {
        NativeToTokenSend.value = false
        if (error.error?.code === 4001) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: error.error.message// t("pages.wallet.swap.user_rejected_the_transaction")
          })
        } else {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.error_occured_check_logs")
          })
          api.error("/pages/wallet/swap", "confirmExchangeTokens:exchangeTokens", error.stack || error)
        }
        TokenToNativeSend.value = false
      }
      newTokenTx.balance = await getTokenBalance()
    }

    const switchChain = async () => {
      try {
        const chain = getChain()
        await ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: `0x${chain.id.toString(16)}` }]
        })
      } catch (error) {
        if (error?.code === 4001) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.user_rejected_the_transaction")
          })
        } else {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.error_occured_check_logs")
          })
          await api.error("/pages/wallet/swap", "switchChain", error.stack || error)
        }
        await api.error("/pages/wallet/swap", "switchChain", error.stack || error)
      }
    }

    const requestAddAsset = async () => {
      try {
        const chain = getChain()

        const wasAdded = await ethereum.request({
          method: "wallet_watchAsset",
          params: {
            type: "ERC20",
            options: {
              address: chain.token_address,
              symbol: selectedNetwork.value.symbol,
              decimals: 18,
              image: "https://raw.githubusercontent.com/Arqma/media-kit/main/exeq.svg"
            }
          }
        })

        if (!wasAdded) {
          await api.error("/pages/wallet/swap", "requestAddAsset was not added")
        }
      } catch (error) {
        if (error?.code === 4001) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.user_rejected_the_transaction")
          })
        } else {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.error_occured_check_logs")
          })
          await api.error("/pages/wallet/swap", "exchangeTokens:exchangeTokens", error.stack || error)
        }
        await api.error("/pages/wallet/swap", "requestAddAsset", error.stack || error)
      }
    }

    const getChain = () => {
      try {
        const network = ethereum_network.value.find(nw => {
          return nw.token_name === selectedNetwork.value.name
        })
        if (!network) {
          return ethereum_network.value[0]
        }
        return network
      } catch (error) {
        api.error("/pages/wallet/swap", "getChain", error.stack || error)
      }
      return ethereum_network.value[0]
    }

    const acceptTransfer = async (signature_data) => {
      try {
        if (signature_data.network !== selectedNetwork.value.name) {
          await setNetwork(networks.value.find(c => c.name === signature_data.network))
          await switchChain()
        }
        transactionHash.value = null
        showCopy.value = false
        if (!!signature_data.signature) {
          NativeToTokenSend.value = true
          const chain = getChain()
          const web3 = new Web3(ethereum)
          const bridgeContract = new web3.eth.Contract(bridgeABI, chain.bridge_address)
          transaction_status.value = t("pages.wallet.swap.requesting_transfer") // "Requesting Transfer"
          const data = await bridgeContract.methods.acceptTransfer(signature_data.to,
            signature_data.amount,
            signature_data.blockNumber,
            signature_data.blockHash,
            signature_data.transactionHash,
            signature_data.logIndex,
            signature_data.nonce,
            signature_data.deadline,
            signature_data.signature).send({ from: signature_data.to })
          transactionHash.value = data.transactionHash
          transaction_status.value = t("pages.wallet.swap.transaction_completed") // "Transaction Completed"
          showCopy.value = true
          newTx.amount = 0
          newTokenTx.tokenAmount = 0
          e$.value.$reset()
          api.send("wallet", "remove_signature_data", {
            ethereumAddress: signature_data.to,
            height: signature_data.blockNumber,
            signature: signature_data.signature
          })
          await $store.dispatch("gateway/set_processing_signature_data", signature_data.signature)
        }
      } catch (error) {
        if (error.error?.code === 4001) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.user_rejected_the_transaction")
          })
        } else {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.error_occured_check_logs")
          })
          await api.error("/pages/wallet/swap", "acceptTransfer", error.stack || error)
        }
        NativeToTokenSend.value = false
      }
      newTokenTx.balance = await getTokenBalance()
    }

    const buildSignature = async (web3) => {
      try {
        const chain = getChain()
        const nonce = await getNonce(web3, bridgeABI, chain.bridge_address)
        const deadline = Date.now() + (1000 * 60 * 60) // 1 hour expiry
        const msgParams = JSON.stringify({
          domain: {
            name: "Bridge",
            version: "1",
            chainId: chain.id,
            verifyingContract: chain.bridge_address
          },
          message: {
            to: newTokenTx.address,
            amount: web3.utils.toWei(newTokenTx.tokenAmount, "ether"),
            nonce: nonce.toString(),
            deadline: deadline.toString()
          },
          primaryType: "exchangeTokens",
          types: {
            EIP712Domain: [
              { name: "name", type: "string" },
              { name: "version", type: "string" },
              { name: "chainId", type: "uint256" },
              { name: "verifyingContract", type: "address" }
            ],
            exchangeTokens: [
              { name: "to", type: "string" },
              { name: "amount", type: "uint256" },
              { name: "nonce", type: "uint256" },
              { name: "deadline", type: "uint256" }
            ]
          }
        })

        const params = [newTokenTx.tokenAddress, msgParams]
        const method = "eth_signTypedData_v4"
        const signature = await ethereum.request({
          method,
          params,
          from: newTokenTx.tokenAddress
        })
        return { nonce, deadline, signature }
      } catch (error) {
        if (error?.code === 4001) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.user_rejected_the_transaction")
          })
        } else {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("pages.wallet.swap.error_occured_check_logs")
          })
          await api.error("/pages/wallet/swap", "exchangeTokens:exchangeTokens", error.stack || error)
        }

        await api.error("/pages/wallet/swap", "buildSignature", error.stack || error)
      }
    }

    return {
      t,
      v$,
      e$,
      TokenToNativeSend,
      NativeToTokenSend,
      confirmXEQSend,
      sending,
      newTx,
      newTokenTx,
      selectedNetwork,
      networks,
      theme,
      view_only,
      unlocked_balance,
      tx_status,
      stake_status,
      is_ready,
      is_able_to_send,
      address_placeholder,
      tx_statusWatcher,
      setNetwork,
      getAmount,
      send,
      requestToExchangeTokens,
      showPasswordConfirmation,
      arqmaField,
      connectWallet,
      connectButtonLabel,
      Formatarqma,
      transaction_status,
      transactionHash,
      copyAddress,
      showCopy,
      openExplorer,
      copy,
      requestAddAsset,
      disconnected,
      acceptTransfer,
      SwapListTabular,
      maxHeight,
      tab,
      isDevelopment
    }
  }
})
</script>
<style scoped>
.scroller {
    max-height: v-bind(maxHeight);
    overflow: auto;
}
</style>

<style lang="scss">
.transfer-text {
    font-size: 2em;
    line-height: .75em;
    font-weight: bold;
}
</style>
