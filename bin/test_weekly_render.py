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
    def test_monthly_compounding_and_missing_day(self):
        rows=[dict(date='2026-08-03',twr=10,qqq_ret=0),dict(date='2026-08-04',twr=-10,qqq_ret=0)]
        expected={'2026-08-03','2026-08-04'}
        self.assertAlmostEqual(r.monthly_totals(rows,'2026-08',expected)['twr'],-1)
        self.assertIsNone(r.monthly_totals(rows[:1],'2026-08',expected))
        self.assertIsNone(r.monthly_totals(rows+rows[:1],'2026-08',expected))
        for invalid in (-100,float('nan'),float('inf')):
            rows[0]['twr']=invalid
            self.assertIsNone(r.monthly_totals(rows,'2026-08',expected))

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
            self.assertLessEqual(selection['characters'],85000)


if __name__=='__main__': unittest.main()
