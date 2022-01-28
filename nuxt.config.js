export default {
  target: 'static',
  head: {
    title: 'Polygonum Cases Balance',
    htmlAttrs: {
      lang: 'en'
    },
    meta: [
      { charset: 'utf-8' },
      { name: 'viewport', content: 'width=device-width, initial-scale=1' },
      { hid: 'description', name: 'description', content: 'Show my POG boxes' }
    ]
  },
  components: true,
  css: [],
  plugins: ['plugins/ethers.js'],
 router: {
   base: '/projects/POG/dist/'
 }
}
