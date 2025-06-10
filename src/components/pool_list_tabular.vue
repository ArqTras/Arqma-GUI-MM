<template>
  <div
    class="pool-list-tabular"
  >
    <template v-if="stakedPools.length === 0">
      <p class="q-pa-md q-mb-none">
        {{ $t('components.pool_list_tabular.no_staked_pools_found') }}
      </p>
    </template>

    <template v-else>
      <q-list
        link
        no-border
        :dark="theme == 'dark'"
        class="column"
      >
        <q-item
          v-for="item in stakedPools"
          :key="item.service_node_pubkey"
          class="arqma-list-item transaction"
          clickable
        >
          <q-item-section class="col-1 type1">
            <div>{{ $t('components.pool_list_tabular.operator') }}</div>
          </q-item-section>

          <q-item-label class="col-4 main">
            <q-item-label class="meta">
              {{ $t('components.pool_list_tabular.oracle_node_id') }}
            </q-item-label>
            <q-item-label caption>
              {{ item.service_node_pubkey }}
            </q-item-label>
          </q-item-label>

          <q-item-label class="col-1 meta">
            <div>{{ $t('components.pool_list_tabular.stakers') }}{{ item.contributors.length.toLocaleString() }}</div>
          </q-item-label>

          <q-item-label class="col-1 meta">
            <div>
              <template v-if="item.lockup.amount === ''">
                {{ $t('components.pool_list_tabular.lock_up') }}
              </template>
              <template v-else>
                {{ $t('components.pool_list_tabular.expiring') }}&nbsp;{{ item.lockup.amount }}&nbsp;{{ $t(item.lockup.i18n) }}
              </template>
            </div>
          </q-item-label>

          <q-item-label class="col-2 meta">
            <div>{{ $t('components.pool_list_tabular.staked') }}{{ item.staked }} ARQ</div>
          </q-item-label>

          <q-item-label class="col-2 meta">
            <div>{{ $t('components.pool_list_tabular.available') }}{{ item.available }} ARQ</div>
          </q-item-label>

          <q-item-label class="col-1 meta">
            <div>{{ !!item.equity ? `${t('components.pool_list_tabular.equity')}${item.equity}%`: "" }}</div>
          </q-item-label>

          <q-menu
            context-menu
            transition-show="flip-up"
            transition-hide="flip-down"
          >
            <q-list
              separator
              style="min-width: 150px; max-height: 300px"
            >
              <q-item
                v-if="item.operator && item.requested_unlock_height === 0"
                v-close-popup
                clickable
                @click="deregisterServiceNode(item.service_node_pubkey, $event)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.deregister_oracle_node') }}</q-item-section>
              </q-item>
              <q-item
                v-close-popup
                clickable
                @click="copyOracleNodeId(item.service_node_pubkey, $event)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.copy_oracle_node_id') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="openExplorer(item.service_node_pubkey)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.view_on_explorer') }}</q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-item>
      </q-list>
    </template>

    <template v-if="filtered_pools.length">
      <q-list
        link
        no-border
        :dark="theme == 'dark'"
        class="column"
      >
        <q-item
          v-for="item in filtered_pools"
          :key="item.service_node_pubkey"
          class="arqma-list-item transaction"
          clickable
          @click="handleClick(item)"
        >
          <q-item-section class="col-1 type">
            <div>{{ item.is_contributor ? t('components.pool_list_tabular.contributor'): "&nbsp;" }}</div>
          </q-item-section>

          <q-item-label class="col-4 main">
            <q-item-label class="meta">
              {{ $t('components.pool_list_tabular.oracle_node_id') }}
            </q-item-label>
            <q-item-label caption>
              {{ item.service_node_pubkey }}
            </q-item-label>
          </q-item-label>

          <q-item-label class="col-1 meta">
            <div>{{ $t('components.pool_list_tabular.stakers') }}{{ item.contributors.length.toLocaleString() }}</div>
          </q-item-label>

          <q-item-label class="col-1 meta">
            <div>
              <template v-if="item.lockup.amount === ''">
                {{ $t('components.pool_list_tabular.lock_up') }}
              </template>
              <template v-else>
                {{ $t('components.pool_list_tabular.expiring') }}&nbsp;{{ item.lockup.amount }}&nbsp;{{ $t(item.lockup.i18n) }}
              </template>
            </div>
          </q-item-label>

          <q-item-label class="col-2 meta">
            <div>{{ $t('components.pool_list_tabular.staked') }}{{ item.staked }} ARQ</div>
          </q-item-label>

          <q-item-label class="col-2 meta">
            <div>{{ $t('components.pool_list_tabular.available') }}{{ item.available }} ARQ</div>
          </q-item-label>

          <q-item-label class="col-1 meta">
            <div>{{ !!item.equity ? `${t('components.pool_list_tabular.equity')}${item.equity}%`: "" }}</div>
          </q-item-label>

          <q-menu
            context-menu
            transition-show="flip-up"
            transition-hide="flip-down"
          >
            <q-list
              separator
              style="min-width: 150px; max-height: 300px"
            >
              <q-item
                v-close-popup
                clickable
                @click="addToAddressBook(item)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.add_operator_to_addressbook') }}</q-item-section>
              </q-item>

              <q-item
                v-if="item.is_contributor && item.requested_unlock_height === 0"
                v-close-popup
                clickable
                @click="deregisterServiceNode(item.service_node_pubkey, $event)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.deregister_oracle_node') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="copyOracleNodeId(item.service_node_pubkey, $event)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.copy_oracle_node_id') }}</q-item-section>
              </q-item>

              <q-item
                v-close-popup
                clickable
                @click="openExplorer(item.service_node_pubkey)"
              >
                <q-item-section>{{ $t('components.pool_list_tabular.view_on_explorer') }}</q-item-section>
              </q-item>
            </q-list>
          </q-menu>
        </q-item>
      </q-list>
    </template>
  </div>

  <q-dialog
    v-model="confirmSend"
    class="column"
    transition-show="flip-up"
    transition-hide="flip-down"
  >
    <q-card :dark="theme == 'dark'">
      <q-card-section class="column justify-center items-center">
        <h5>{{ $t('components.pool_list_tabular.confirm_amount_to_stake') }}</h5>
        <p>{{ $t('components.pool_list_tabular.oracle_id') }}</p>
        <p>{{ oracleKey }}</p>
        <p v-if="unlocked_balance > stake_data.maxAmount">
          {{ $t('components.pool_list_tabular.max_amount') }}{{ stake_data.maxAmount }}
        </p>
        <p v-else>
          {{ $t('components.pool_list_tabular.max_amount') }}{{ (unlocked_balance).toLocaleString() }}
        </p>
        <p>{{ $t('components.pool_list_tabular.min_amount') }}{{ stake_data.minAmount }}</p>

        <arqmaField
          :label="$t('components.pool_list_tabular.amount')"
          style="width: 50%;"
          :error="v$.stakeAmount.$error"
        >
          <q-input
            v-model="stake_data.stakeAmount"
            type="number"
            :min="stake_data.minAmount"
            :max="stake_data.maxAmount"
            :placeholder="stake_data.minAmount"
            borderless
            dense
            @blur="v$.stakeAmount.$validate()"
          />
          <q-btn
            color="positive"
            :text-color="theme == 'dark' ? 'white' : 'dark'"
            @click="stake_data.stakeAmount = Math.min(stake_data.maxAmount, unlocked_balance)"
          >
            Max
          </q-btn>
        </arqmaField>
      </q-card-section>
      <q-card-actions class="row justify-end items-center">
        <q-btn
          v-if="unlocked_balance >= stake_data.minAmount"
          style="background-color: #005bc6"
          color="positive"
          :label="$t('components.pool_list_tabular.confirm_stake')"
          :disable="v$.stakeAmount.$error"
          @click="stake(), (confirmSend = false)"
        />
        <q-btn
          v-else
          style="background-color: #db1010; cursor: not-allowed"
          :label="$t('components.pool_list_tabular.not_enough_coins')"
          :disable="true"
        />
      </q-card-actions>
    </q-card>
  </q-dialog>
</template>

<script>
import { computed, defineComponent, ref, watch, reactive } from "vue"
import { useStore } from "vuex"
import { useQuasar } from "quasar"
import arqmaField from "components/arqma_field"
import { usePasswordConfirmation } from "src/composables/wallet_password"
import { useVuelidate } from "@vuelidate/core"
import { required, integer, between } from "@vuelidate/validators"
import { useI18n } from "vue-i18n"

export default defineComponent({
  name: "PoolListTabular",
  components: {
    arqmaField
  },
  setup () {
    const $store = useStore()
    const $q = useQuasar()
    const { t } = useI18n()

    const { showPasswordConfirmation } = usePasswordConfirmation()

    const tx_type = ref(t("components.pool_list_tabular.all"))
    const tx_txid = ref("")
    const status = ref(t("components.pool_list_tabular.not_joined"))
    const confirmSend = ref(false)
    const oracleKey = ref("")
    const oracleAddress = ref("")
    const tvl = ref(0)
    const stake_data = reactive({
      maxAmount: 100,
      minAmount: 100,
      stakeAmount: 100
    })

    // Validations
    const rules = computed(() => {
      return {
        stakeAmount: { between: between(stake_data.minAmount, stake_data.maxAmount), integer, required }
      }
    })
    const v$ = useVuelidate(rules, stake_data)

    const coinUnits = 10 ** 9

    // Computed props
    const theme = computed(() => $store.state.gateway.app.config.appearance.theme)
    const all_pools = computed(() => $store.state.gateway.pools.pool_list)
    const filtered_pools = computed(() => $store.getters["gateway/filtered_pools"])
    const tx_status = computed(() => $store.state.gateway.tx_status)
    const stake_status = computed(() => $store.state.gateway.service_node_status.stake)
    const deregister_status = computed(() => $store.state.gateway.service_node_status.unlock)
    const unlocked_balance = computed(() => $store.state.gateway.wallet.info.unlocked_balance / coinUnits)
    const stakedPools = computed(() => $store.getters["gateway/staked_pools"] || [])
    const info = computed(() => {
      return $store.state.gateway.wallet.info
    })
    const state = computed(() => {
      return $store.state
    })

    // Watchers
    const deregister_statusWatcher = watch(deregister_status, (newVal, oldVal) => {
      try {
        if (newVal.code === oldVal.code) return
        switch (newVal.code) {
          case 400:
            $q.notify({
              type: "positive",
              timeout: 10000,
              message: deregister_status.value.message
            })
            break
          case -400:
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: deregister_status.value.message
            })
            break
        }
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "deregister_statusWatcher", error.stack || error)
      }
    })

    const stake_statusWatcher = watch(stake_status, (newVal, oldVal) => {
      try {
        console.log("stake_statusWatcher", newVal, oldVal)
        if (newVal.code === oldVal.code) return
        switch (newVal.code) {
          case 0:
            $q.notify({
              type: "positive",
              timeout: 3000,
              message: stake_status.value.message
            })
            service_node.value = {
              key: "",
              amount: 0,
              award_address: ""
            }
            break
          case -1:
            $q.notify({
              type: "negative",
              timeout: 3000,
              message: stake_status.value.message
            })
            break
        }
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "stake_statusWatcher", error.stack || error)
      }
    })

    const tx_statusWatcher = watch(tx_status, (newVal, oldVal) => {
      try {
        const { code, message } = newVal
        switch (code) {
          case 300:
            $q
              .dialog({
                title: t("components.pool_list_tabular.tx_status_title"),
                message,
                ok: {
                  label: t("components.pool_list_tabular.tx_status_ok_label"),
                  color: "positive"
                },
                cancel: {
                  flat: true,
                  label: t("components.pool_list_tabular.tx_status_cancel_label"),
                  color: "red"
                },
                dark: theme.value === "dark",
                color: theme.value === "dark" ? "white" : "dark",
                transitionShow: "flip-up",
                transitionHide: "flip-down"
              }).onOk(() => {
                api.send("wallet", "relay_stake", {})
              }).onDismiss(() => {})
              .onCancel(() => {})
            break
          case -300: // stake failed
            $q.notify({
              type: "negative",
              timeout: 3000,
              message
            })
            break
        }
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "tx_statusWatcher", error.stack || error)
      }
    })

    // Methods
    const handleClick = (item) => {
      try {
        stake_data.maxAmount = (item.staking_requirement - item.total_contributed) / coinUnits
        if (stake_data.maxAmount > 0) {
          stake_data.stakeAmount = 100
          oracleKey.value = item.service_node_pubkey
          oracleAddress.value = item.operator_address
          confirmSend.value = true
        }
      } catch (error) {
        api.error("/pages/wallet/staking-pools", "handleClick", error.stack || error)
      }
    }

    const stake = async (key, address, amount) => {
      try {
        await v$.value.$validate()
        if (v$.value.stakeAmount.$error) {
          $q.notify({
            type: "negative",
            timeout: 3000,
            message: t("components.pool_list_tabular.invalid_stake_amount")
          })
          return
        }

        const dialog = await showPasswordConfirmation({
          title: t("components.pool_list_tabular.show_password_confirmation_title"),
          noPasswordMessage: t("components.pool_list_tabular.show_password_confirmation_message"),
          ok: {
            label: t("components.pool_list_tabular.show_password_confirmation_ok_label"),
            color: "positive"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })
        dialog.onOk((password) => {
          api.send("wallet", "stake", {
            password,
            amount: stake_data.stakeAmount,
            key: oracleKey.value,
            destination: info.value.address
          })
        })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        await api.error("/pages/wallet/staking-pools", "stake", error.stack || error)
      }
    }

    const openExplorer = async (nodeId) => {
      try {
        api.send("core", "open_explorer", { type: "service_node", id: nodeId })
      } catch (error) {
        await api.error("components/pool_list_tabular", "openExplorer", error.stack || error)
      }
    }

    const deregisterServiceNode = async (nodeId, event) => {
      try {
        event.stopPropagation()
        const dialog = await showPasswordConfirmation({
          title: t("components.pool_list_tabular.deregister_service_node_title"),
          message: t("components.pool_list_tabular.deregister_service_node_message"),
          ok: {
            label: t("components.pool_list_tabular.deregister_service_node_ok_label"),
            color: "negative"
          },
          cancel: {
            flat: true,
            label: t("components.pool_list_tabular.deregister_service_node_cancel_label"),
            color: "primary"
          },
          dark: theme.value === "dark",
          color: theme.value === "dark" ? "white" : "dark"
        })
        dialog.onOk((password) => {
          api.send("wallet", "unlock_stake", { password, service_node_key: nodeId, confirmed: true })
        })
          .onDismiss(() => {})
          .onCancel(() => {})
      } catch (error) {
        await api.error("components/pool_list_tabular", "deregisterServiceNode", error.stack || error)
      }
    }

    const copyOracleNodeId = async (nodeId, event) => {
      try {
        event.stopPropagation()
        api.writeText(nodeId)
        $q.notify({
          type: "positive",
          timeout: 3000,
          message: t("components.pool_list_tabular.copied_oracle_nodeid_to_clipboard")
        })
      } catch (error) {
        await api.error("components/pool_list_tabular", "copyNodeId", error.stack || error)
      }
    }

    const addToAddressBook = async (item) => {
      try {
        const params = {
          address: item.operator_address,
          description: t("components.pool_list_tabular.favourite_operator"),
          name: `service_node_operator${randomInt(0, 50000)}`,
          starred: true
        }
        api.send("wallet", "add_address_book", params)
      } catch (error) {
        await api.error("components/pool_list_tabular", "addToAddressBook", error.stack || error)
      }
    }

    const randomInt = (min, max) => {
      return Math.floor(Math.random() * (max - min + 1) + min)
    }

    return {
      t,
      v$,
      copyOracleNodeId,
      deregisterServiceNode,
      deregister_statusWatcher,
      openExplorer,
      filtered_pools,
      tx_type,
      tx_txid,
      status,
      confirmSend,
      oracleKey,
      oracleAddress,
      tvl,
      stake_data,
      theme,
      all_pools,
      tx_status,
      stake_status,
      unlocked_balance,
      info,
      state,
      stake_statusWatcher,
      tx_statusWatcher,
      handleClick,
      stake,
      arqmaField,
      stakedPools,
      addToAddressBook
    }
  }
})
</script>

<style lang="scss">
</style>
