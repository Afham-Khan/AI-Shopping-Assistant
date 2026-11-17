const nodemailer = require('nodemailer');

let transporter;
const outbox = [];

const getTransporter = () => {
  if (!transporter) {
    const port = Number(process.env.SMTP_PORT) || 465;
    transporter = nodemailer.createTransport({
      host: process.env.SMTP_HOST,
      port,
      secure: port === 465,
      auth: { user: process.env.SMTP_USER, pass: process.env.SMTP_PASS },
    });
  }
  return transporter;
};

// tests read the outbox; without smtp creds the mail is printed so the otp is still usable
const sendMail = async ({ to, subject, text, html }) => {
  if (process.env.NODE_ENV === 'test') {
    outbox.push({ to, subject, text });
    return;
  }
  if (!process.env.SMTP_USER) {
    console.log(`\n[MAIL] to=${to} | ${subject}\n${text}\n`);
    return;
  }
  await getTransporter().sendMail({ from: process.env.MAIL_FROM, to, subject, text, html });
};

module.exports = { sendMail, outbox };
