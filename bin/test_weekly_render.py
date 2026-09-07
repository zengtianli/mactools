"""Monthly evidence boundaries and balanced model input; no external generation."""
import json
from pathlib import Path
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch
import weekly_render as r


def record(day):
    return dict(id=day,title='Recorded work',text='正文'*8000,source='https://example.test/'+day,group='daily',date=day)


class MonthlyRenderTests(unittest.TestCase):
    def test_non_json_response_retries_once_then_fails_closed(self):
        records=[record('2026-08-03')]
        good=json.dumps(dict(hook='记录',summary='记录',items=[dict(title='进展',text='真实记录',source_ids=['2026-08-03'])],next_steps=[]))
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module') as module:
            module.return_value.chat.side_effect=['已知悉，备份完成。',good]
            self.assertEqual(r._summary('water','2026-08-09',records,Path(temp))['hook'],'记录')
            self.assertEqual(module.return_value.chat.call_count,2)
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module') as module:
            module.return_value.chat.return_value='已知悉，备份完成。'
            with self.assertRaises(ValueError):
                r._summary('water','2026-08-09',records,Path(temp))
            self.assertEqual(module.return_value.chat.call_count,2)
            self.assertFalse([p for p in Path(temp).glob('summary-*.json') if p.name != 'summary-selection.json'])

    def test_long_multisection_summary_keeps_source_validation(self):
        row = record('2026-08-03')
        value = dict(hook='有变化', summary='已有依据', items=[dict(title=f'进展{i}', text='甲'*180+'\n\n'+'乙'*180, source_ids=[row['id']]) for i in range(12)], next_steps=[dict(text='建议'+('查'*500), source_ids=[row['id']])])
        self.assertIs(r.validate_summary(value, [row]), value)
        value['items'][0]['source_ids'] = ['unknown']
        with self.assertRaisesRegex(ValueError, '来源'):
            r.validate_summary(value, [row])
        value['items'][0]['source_ids'] = [row['id']]
        value['items'][0]['text'] = '甲'*1801
        with self.assertRaisesRegex(ValueError, '长度'):
            r.validate_summary(value, [row])

    def test_paragraphs_escape_html_without_flattening(self):
        self.assertEqual(r._paragraphs('第一段 <script>&\n换行。\n\n第二段。'), '第一段 &lt;script&gt;&amp; 换行。\n\n第二段。')

    def test_render_folds_named_sources_after_prose(self):
        row = record('2026-08-03')
        row['title'] = '一次实际记录'
        value = dict(hook='有变化', summary='已有依据', items=[dict(title='具体进展', text='第一段。\n\n第二段。', source_ids=[row['id']])], next_steps=[])
        with tempfile.TemporaryDirectory() as temp:
            folder=Path(temp)
            post=SimpleNamespace(zh_md=folder/'weekly-development-2026-08-09.md')
            bp=SimpleNamespace(sites=lambda:[SimpleNamespace(key='blog',images_rel='images/blog',content_dir=folder)],post=lambda slug:post)
            with patch.object(r,'_summary',return_value=value),patch.object(r,'_module',return_value=bp),patch.object(r,'_charts'),patch.object(r,'_cover'),patch.object(r.subprocess,'run'):
                r.render('development','2026-08-09',[row],folder)
            content=post.zh_md.read_text()
            self.assertIn('### 具体进展\n\n第一段。\n\n第二段。',content)
            prose,sources=content.split('<details>')
            self.assertNotIn('来源 ',content)
            self.assertNotIn('example.test',prose)
            self.assertIn('2026-08-03 · 项目记录 · daily',sources)
            self.assertIn(row['source'],sources)
            self.assertIn('</details>',sources)
            with patch.object(r,'_summary',return_value=value),patch.object(r,'_module',return_value=bp),patch.object(r,'_charts'),patch.object(r,'_cover'),patch.object(r.subprocess,'run'):
                r.render('development','2026-09-01',[row],folder,'monthly')
            self.assertIn('统计月份：2026-08，完整自然月',(folder/'monthly-development-2026-08.md').read_text())

    def test_monthly_compounding_and_missing_day(self):
        rows=[dict(date='2026-08-03',twr=10,qqq_ret=0),dict(date='2026-08-04',twr=-10,qqq_ret=0)]
        expected={'2026-08-03','2026-08-04'}
        self.assertAlmostEqual(r.monthly_totals(rows,'2026-08',expected)['twr'],-1)
        self.assertIsNone(r.monthly_totals(rows[:1],'2026-08',expected))
        self.assertIsNone(r.monthly_totals(rows+rows[:1],'2026-08',expected))
        for invalid in (-100,float('nan'),float('inf')):
            rows[0]['twr']=invalid
            self.assertIsNone(r.monthly_totals(rows,'2026-08',expected))

    def test_weekly_totals_require_calendar_days_not_only_records(self):
        days=['2026-08-03','2026-08-04']
        ledger=[dict(date=day,twr=rate,qqq_ret=0,buffer_pct=32,buffer_caliber='结算后') for day,rate in zip(days,(10,-10))]
        class Figure:
            def __init__(self,*args): self.w,self.h=args
            def __getattr__(self,name): return lambda *args,**kwargs:'<svg/>' if name=='svg' else None
        fig=SimpleNamespace(Fig=Figure,PAL={key:key for key in ('primary','accent','sub','grid')},export=lambda *args:None)
        fig.bars=lambda *args,**kwargs:None
        calendar=SimpleNamespace(require_calendar_coverage=lambda day:None,is_trading_day=lambda day:str(day) in days)
        def module(name,path):
            return calendar if name=='quantlab.tcal' else SimpleNamespace(_rows=lambda:ledger,LEDGER='fixture')
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module',side_effect=module):
            folder=Path(temp)
            post=SimpleNamespace(images_dir=folder,zh_md=folder/'post.md',slug='weekly-investment-2026-08-09')
            post.zh_md.write_text('## 本周做了什么\n\n<details>原记录</details>')
            r._investment_charts(post,[record(day) for day in days],fig,'weekly','2026-08-09')
            values=json.loads((folder/'weekly-scoreboard.json').read_text())
            self.assertAlmostEqual(values['totals']['twr'],-1)
            self.assertEqual(values['period'],dict(start='2026-08-02',end_exclusive='2026-08-09'))
            self.assertIn('周度记分表',post.zh_md.read_text())
            self.assertTrue(post.zh_md.read_text().endswith('<details>原记录</details>'))
            r._investment_charts(post,[record(days[0])],fig,'weekly','2026-08-09')
            self.assertIsNone(json.loads((folder/'weekly-scoreboard.json').read_text())['totals'])

    def test_return_fallback_preserves_missing_buffer_and_source_values(self):
        days=[f'2026-08-{day:02}' for day in range(3,24)]
        ledger=[dict(date=day,twr=1.25,qqq_ret=-.75,buffer_pct=32.0,buffer_caliber='结算后') for day in days[1:]]
        ledger[1]['buffer_caliber'] = '4pm(当日无到期腿,两口径同值)'
        class Figure:
            def __init__(self,*args): self.w,self.h=args
            def __getattr__(self,name):
                return lambda *args,**kwargs: '<svg/>' if name=='svg' else None
        fig=SimpleNamespace(Fig=Figure,PAL={key:key for key in ('primary','accent','sub','grid')},export=lambda *args:None)
        def module(name,path):
            if name=='scoreboard': return SimpleNamespace(_rows=lambda:ledger,LEDGER='fixture-ledger')
            if name=='day_vs_qqq': return SimpleNamespace(row=lambda day:dict(date=str(day),twr=1.6441211741105057,qqq_ret=1.7558394744109713))
            raise AssertionError(name)
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module',side_effect=module),patch.object(r,'monthly_totals',return_value=None):
            folder=Path(temp)
            post=SimpleNamespace(images_dir=folder,zh_md=folder/'post.md',slug='monthly-investment-2026-08')
            post.zh_md.write_text('本月逐日记录数量')
            self.assertTrue(r._investment_charts(post,[record(day) for day in days],fig,'monthly'))
            values=json.loads((folder/'monthly-scoreboard.json').read_text())
            self.assertEqual(values['missing_buffer_dates'],['2026-08-03'])
            self.assertEqual(values['missing_return_dates'],[])
            self.assertEqual(values['rows'][0]['twr'],1.6441211741105057)
            self.assertIsNone(values['rows'][0]['buffer_pct'])
            self.assertEqual(len(ledger),20)
            self.assertIn('当日无到期腿',post.zh_md.read_text())
            ledger[1]['buffer_caliber'] = '4pm(未核实到期腿)'
            with self.assertRaisesRegex(ValueError,'口径'):
                r._investment_charts(post,[record(day) for day in days],fig,'monthly')

    def test_many_projects_still_cover_all_month_segments(self):
        records=[]
        for group in range(70):
            for day in (1,8,15,22,29):
                item=record(f'2026-08-{day:02}')
                item.update(id=f'{group}-{day}',group=f'project-{group:03}')
                records.append(item)
        def chat(system,payload,**kwargs):
            data=json.loads(payload)
            self.assertEqual({x['date'] for x in data['records']},{f'2026-08-{d:02}' for d in (1,8,15,22,29)})
            return json.dumps(dict(hook='已有记录',summary='整理月度记录',items=[dict(title='进展',text='依据记录',source_ids=[data['records'][0]['id']])],next_steps=[]))
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module',return_value=SimpleNamespace(chat=chat)):
            r._summary('development','2026-09-01',records,Path(temp),'monthly')

    def test_full_month_and_exclusive_endpoint(self):
        r.validate_records([record('2026-08-01'),record('2026-08-31')],'2026-09-01','monthly')
        for day in ('2026-07-31','2026-09-01'):
            with self.assertRaises(ValueError):
                r.validate_records([record(day)],'2026-09-01','monthly')

    def test_non_month_boundary_rejected(self):
        with self.assertRaises(ValueError):
            r.validate_records([record('2026-08-10')],'2026-09-02','monthly')

    def test_all_daily_reviews_fit_monthly_prompt(self):
        records=[record(f'2026-08-{day:02}') for day in range(1,32)]
        captured={}
        def chat(system,payload,**kwargs):
            data=json.loads(payload)
            captured.update(data)
            self.assertIn('月度成果',system)
            self.assertNotIn('model',kwargs)
            return json.dumps(dict(hook='已有记录',summary='整理月度记录',items=[dict(title='进展',text='依据记录',source_ids=[data['records'][0]['id']])],next_steps=[]))
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module',return_value=SimpleNamespace(chat=chat)):
            r._summary('investment','2026-09-01',records,Path(temp),'monthly')
            self.assertEqual({x['date'] for x in captured['records']},{x['date'] for x in records})
            selection=json.loads((Path(temp)/'summary-selection.json').read_text())
            self.assertLessEqual(selection['characters'],220000)
            self.assertEqual(captured['version'],3)
            self.assertGreater(selection['characters'],85000)

    def test_weekly_investment_keeps_daily_middle(self):
        records=[record(f'2026-08-{day:02}') for day in range(3,8)]
        for item in records: item['text']='头'*7000+'中间关键交易'+'尾'*7000
        def chat(system,payload,**kwargs):
            data=json.loads(payload)
            self.assertTrue(all('中间关键交易' in row['text'] for row in data['records']))
            self.assertIn('3000至4500',system)
            return json.dumps(dict(hook='已有记录',summary='整理记录',items=[dict(title='进展',text='依据记录',source_ids=[data['records'][0]['id']])],next_steps=[]))
        with tempfile.TemporaryDirectory() as temp,patch.object(r,'_module',return_value=SimpleNamespace(chat=chat)):
            r._summary('investment','2026-08-09',records,Path(temp))


if __name__=='__main__': unittest.main()
