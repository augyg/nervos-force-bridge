module.exports = {
  content: ['./frontend/**/*.hs'],
  theme: {
    extend: {
      fontFamily: {
        'sans': ['-apple-system', 'BlinkMacSystemFont', 'Segoe UI', 'Roboto', 'Oxygen',
                 'Ubuntu', 'Cantarell', 'Fira Sans', 'Droid Sans', 'Helvetica Neue',
                 'sans-serif'],
      },
      width: {
        '90' : '360px',
        'svg' : '14px',
        'svg-lg' : '24px',
        'svg-logo' : '62px',
      },
      height: {
        'svg' : '14px',
        'svg-lg' : '24px',
        'svg-logo' : '32px',
      },
      colors: {
        primary: {
          DEFAULT: '#00ccc0',
        },
        secondary: {
          DEFAULT: '#b8f0d5',
          'end': '#b8f0ed',
        },
        tertiary: {
          DEFAULT: '#dcf2ed',
          'end': '#d3d9ec',
        },
      },
      boxShadow: {
        'md' : '3px 3px 8px rgba(0, 0, 0, 0.08)',
      },
    },
  },
  plugins: [
    require("tailwindcss-scoped-groups"),
  ],
}
