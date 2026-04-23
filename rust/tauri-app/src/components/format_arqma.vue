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
    digits: {
      type: Number,
      required: false,
      default: 9
    },
    asWei: {
      type: Boolean,
      required: false,
      default: false
    }
  },
  setup (props) {
    const { amount, round, digits, asWei } = toRefs(props)
    const coinUnits = 10 ** 9

    // Computed props
    const value = computed(() => {
      if (asWei.value) {
        return amount.value.toLocaleString()
      } else {
        let val = amount.value / coinUnits
        if (round.value) {
          val = Number(val.toFixed(digits.value))
          return val.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: digits.value })
        }
        return val.toLocaleString(undefined, { minimumFractionDigits: 0, maximumFractionDigits: digits.value })
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
