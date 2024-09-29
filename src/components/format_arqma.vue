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

    // Computed props
    const value = computed(() => {
      if (asWei.value) {
        return amount.value.toLocaleString()
      } else {
        let value = amount.value / 1e9
        if (round.value) {
          value = value.toFixed(4)
        }
        return value.toLocaleString()
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
