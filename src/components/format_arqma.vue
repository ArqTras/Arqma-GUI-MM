<template>
  <span>{{ value }}</span>
</template>

<script>
import { computed, defineComponent, toRefs } from "vue"

export default defineComponent({
  name: "Formatarqma",
  props: {
    amount: {
      required: true,
      type: Number
    },
    round: {
      type: Boolean,
      required: false,
      default: false
    },
    asWei: {
      type: Boolean,
      required: false,
      default: false
    }
  },
  setup (props) {
    const { amount, round, asWei } = toRefs(props)
    const coinUnits = 10 ** 9

    // Computed props
    const value = computed(() => {
      if (asWei.value) {
        return amount.value.toLocaleString()
      } else {
        let val = amount.value / coinUnits
        if (round.value) {
          val = Number(val.toFixed(9))
          return val.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 9 })
        }
        return val.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: 9 })
      }
    })

    return {
      value
    }
  }
})
</script>

<style>
</style>
